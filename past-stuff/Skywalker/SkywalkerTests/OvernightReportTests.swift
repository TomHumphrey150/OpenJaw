//
//  OvernightReportTests.swift
//  SkywalkerTests
//
//  Unit tests for OvernightReportCalculator
//

import XCTest
@testable import Skywalker

final class OvernightReportTests: XCTestCase {

    // MARK: - Filter Overnight Window Tests

    func testFilterOvernightWindow() {
        // Create events within and outside the overnight window
        let date = TestEventData.date(year: 2026, month: 2, day: 1, hour: 0) // Feb 1, midnight
        let calendar = Calendar.current

        let events = [
            // Inside window (6 PM Jan 31 to noon Feb 1)
            TestEventData.jawClenchEvent(at: calendar.date(byAdding: DateComponents(day: -1, hour: 19), to: date)!, count: 1), // 7 PM Jan 31
            TestEventData.jawClenchEvent(at: calendar.date(byAdding: .hour, value: 2, to: date)!, count: 2),  // 2 AM Feb 1
            TestEventData.jawClenchEvent(at: calendar.date(byAdding: .hour, value: 10, to: date)!, count: 3), // 10 AM Feb 1

            // Outside window
            TestEventData.jawClenchEvent(at: calendar.date(byAdding: DateComponents(day: -1, hour: 15), to: date)!, count: 4), // 3 PM Jan 31 (before 6 PM)
            TestEventData.jawClenchEvent(at: calendar.date(byAdding: .hour, value: 14, to: date)!, count: 5), // 2 PM Feb 1 (after noon)
        ]

        let filtered = OvernightReportCalculator.filterEventsToOvernightWindow(events: events, forDate: date)

        XCTAssertEqual(filtered.count, 3)
        XCTAssertTrue(filtered.contains { $0.count == 1 })
        XCTAssertTrue(filtered.contains { $0.count == 2 })
        XCTAssertTrue(filtered.contains { $0.count == 3 })
    }

    func testFilterExcludesOutside() {
        let date = TestEventData.date(year: 2026, month: 2, day: 1, hour: 0)
        let events = TestEventData.outsideWindowEvents

        let filtered = OvernightReportCalculator.filterEventsToOvernightWindow(events: events, forDate: date)

        XCTAssertEqual(filtered.count, 0)
    }

    func testFilterEmptyEvents() {
        let date = Date()
        let filtered = OvernightReportCalculator.filterEventsToOvernightWindow(events: [], forDate: date)

        XCTAssertEqual(filtered.count, 0)
    }

    // MARK: - Events Per Hour Tests

    func testEventsPerHour_Calculation() {
        // 10 events in 5 hours = 2 events/hour
        let eventsPerHour = OvernightReportCalculator.eventsPerHour(
            eventCount: 10,
            totalSleepSeconds: 5 * 3600
        )

        XCTAssertEqual(eventsPerHour, 2.0, accuracy: 0.001)
    }

    func testEventsPerHour_ZeroSleep() {
        // Zero sleep time should return 0, not crash with division by zero
        let eventsPerHour = OvernightReportCalculator.eventsPerHour(
            eventCount: 10,
            totalSleepSeconds: 0
        )

        XCTAssertEqual(eventsPerHour, 0)
    }

    func testEventsPerHour_ZeroEvents() {
        let eventsPerHour = OvernightReportCalculator.eventsPerHour(
            eventCount: 0,
            totalSleepSeconds: 8 * 3600
        )

        XCTAssertEqual(eventsPerHour, 0)
    }

    func testEventsPerHour_FractionalResult() {
        // 7 events in 3 hours = 2.333... events/hour
        let eventsPerHour = OvernightReportCalculator.eventsPerHour(
            eventCount: 7,
            totalSleepSeconds: 3 * 3600
        )

        XCTAssertEqual(eventsPerHour, 7.0 / 3.0, accuracy: 0.001)
    }

    // MARK: - Events By Phase Tests

    func testEventsByPhase_Single() {
        let now = Date()

        // Create a single sleep sample and event within it
        let sleepSamples = [
            HealthKitService.SleepSample(
                startDate: now,
                endDate: now.addingTimeInterval(3600),
                phase: .deep
            )
        ]

        let events = [
            TestEventData.jawClenchEvent(at: now.addingTimeInterval(1800), count: 1) // Middle of deep sleep
        ]

        let counts = OvernightReportCalculator.eventsByPhase(events: events, sleepSamples: sleepSamples)

        XCTAssertEqual(counts[.deep], 1)
        XCTAssertNil(counts[.core])
        XCTAssertNil(counts[.rem])
    }

    func testEventsByPhase_Multiple() {
        let now = Date()

        let sleepSamples = [
            HealthKitService.SleepSample(
                startDate: now,
                endDate: now.addingTimeInterval(3600),
                phase: .core
            ),
            HealthKitService.SleepSample(
                startDate: now.addingTimeInterval(3600),
                endDate: now.addingTimeInterval(7200),
                phase: .deep
            ),
            HealthKitService.SleepSample(
                startDate: now.addingTimeInterval(7200),
                endDate: now.addingTimeInterval(10800),
                phase: .rem
            ),
        ]

        let events = [
            TestEventData.jawClenchEvent(at: now.addingTimeInterval(1800), count: 1),  // Core
            TestEventData.jawClenchEvent(at: now.addingTimeInterval(5400), count: 2),  // Deep
            TestEventData.jawClenchEvent(at: now.addingTimeInterval(5500), count: 3),  // Deep
            TestEventData.jawClenchEvent(at: now.addingTimeInterval(9000), count: 4),  // REM
        ]

        let counts = OvernightReportCalculator.eventsByPhase(events: events, sleepSamples: sleepSamples)

        XCTAssertEqual(counts[.core], 1)
        XCTAssertEqual(counts[.deep], 2)
        XCTAssertEqual(counts[.rem], 1)
    }

    func testEventsByPhase_NoMatch() {
        // Events outside any sleep phase should default to awake
        let now = Date()

        let sleepSamples = [
            HealthKitService.SleepSample(
                startDate: now,
                endDate: now.addingTimeInterval(3600),
                phase: .deep
            )
        ]

        let events = [
            TestEventData.jawClenchEvent(at: now.addingTimeInterval(7200), count: 1) // Outside sleep period
        ]

        let counts = OvernightReportCalculator.eventsByPhase(events: events, sleepSamples: sleepSamples)

        XCTAssertEqual(counts[.awake], 1)
        XCTAssertNil(counts[.deep])
    }

    func testEventsByPhase_EmptyEvents() {
        let counts = OvernightReportCalculator.eventsByPhase(events: [], sleepSamples: TestEventData.overnightSleepSamples)

        XCTAssertTrue(counts.isEmpty)
    }

    // MARK: - Filter To Sleep Phases Tests

    func testFilterToSleepPhases() {
        let now = Date()

        let sleepSamples = [
            HealthKitService.SleepSample(
                startDate: now,
                endDate: now.addingTimeInterval(3600),
                phase: .awake
            ),
            HealthKitService.SleepSample(
                startDate: now.addingTimeInterval(3600),
                endDate: now.addingTimeInterval(7200),
                phase: .core
            ),
            HealthKitService.SleepSample(
                startDate: now.addingTimeInterval(7200),
                endDate: now.addingTimeInterval(10800),
                phase: .inBed
            ),
        ]

        let events = [
            TestEventData.jawClenchEvent(at: now.addingTimeInterval(1800), count: 1),  // During awake
            TestEventData.jawClenchEvent(at: now.addingTimeInterval(5400), count: 2),  // During core
            TestEventData.jawClenchEvent(at: now.addingTimeInterval(9000), count: 3),  // During inBed
        ]

        let filtered = OvernightReportCalculator.filterToSleepPhases(events: events, sleepSamples: sleepSamples)

        // Only the event during core sleep should be included (awake and inBed excluded)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.count, 2)
    }

    func testFilterToSleepPhases_AllSleepTypes() {
        let now = Date()

        let sleepSamples = [
            HealthKitService.SleepSample(startDate: now, endDate: now.addingTimeInterval(1000), phase: .core),
            HealthKitService.SleepSample(startDate: now.addingTimeInterval(1000), endDate: now.addingTimeInterval(2000), phase: .deep),
            HealthKitService.SleepSample(startDate: now.addingTimeInterval(2000), endDate: now.addingTimeInterval(3000), phase: .rem),
            HealthKitService.SleepSample(startDate: now.addingTimeInterval(3000), endDate: now.addingTimeInterval(4000), phase: .asleepUnspecified),
        ]

        let events = [
            TestEventData.jawClenchEvent(at: now.addingTimeInterval(500), count: 1),   // Core
            TestEventData.jawClenchEvent(at: now.addingTimeInterval(1500), count: 2),  // Deep
            TestEventData.jawClenchEvent(at: now.addingTimeInterval(2500), count: 3),  // REM
            TestEventData.jawClenchEvent(at: now.addingTimeInterval(3500), count: 4),  // asleepUnspecified
        ]

        let filtered = OvernightReportCalculator.filterToSleepPhases(events: events, sleepSamples: sleepSamples)

        // All events should be included (all are during actual sleep phases)
        XCTAssertEqual(filtered.count, 4)
    }

    // MARK: - Histogram Tests

    func testHistogram_15MinBuckets() {
        let baseTime = TestEventData.date(year: 2026, month: 2, day: 1, hour: 2, minute: 0) // 2:00 AM

        let events = [
            TestEventData.jawClenchEvent(at: baseTime, count: 1),                                                  // 2:00
            TestEventData.jawClenchEvent(at: Calendar.current.date(byAdding: .minute, value: 20, to: baseTime)!, count: 2), // 2:20 -> 2:15 bucket
            TestEventData.jawClenchEvent(at: Calendar.current.date(byAdding: .minute, value: 35, to: baseTime)!, count: 3), // 2:35 -> 2:30 bucket
        ]

        let histogram = OvernightReportCalculator.eventHistogram(events: events, bucketMinutes: 15)

        XCTAssertEqual(histogram.count, 3)

        // Verify buckets are at 2:00, 2:15, 2:30
        let bucketMinutes = histogram.map { Calendar.current.component(.minute, from: $0.time) }
        XCTAssertTrue(bucketMinutes.contains(0))
        XCTAssertTrue(bucketMinutes.contains(15))
        XCTAssertTrue(bucketMinutes.contains(30))
    }

    func testHistogram_SameBucket() {
        // Multiple events in the same 15-minute bucket should aggregate
        let baseTime = TestEventData.date(year: 2026, month: 2, day: 1, hour: 2, minute: 0)

        let events = [
            TestEventData.jawClenchEvent(at: baseTime, count: 1),                                                  // 2:00
            TestEventData.jawClenchEvent(at: Calendar.current.date(byAdding: .minute, value: 5, to: baseTime)!, count: 2),  // 2:05
            TestEventData.jawClenchEvent(at: Calendar.current.date(byAdding: .minute, value: 10, to: baseTime)!, count: 3), // 2:10
        ]

        let histogram = OvernightReportCalculator.eventHistogram(events: events, bucketMinutes: 15)

        XCTAssertEqual(histogram.count, 1) // All in same bucket (2:00-2:14)
        XCTAssertEqual(histogram.first?.count, 3)
    }

    func testHistogram_Empty() {
        let histogram = OvernightReportCalculator.eventHistogram(events: [], bucketMinutes: 15)

        XCTAssertTrue(histogram.isEmpty)
    }

    func testHistogram_Sorted() {
        // Events added out of order should result in sorted histogram
        let baseTime = TestEventData.date(year: 2026, month: 2, day: 1, hour: 2, minute: 0)

        let events = [
            TestEventData.jawClenchEvent(at: Calendar.current.date(byAdding: .minute, value: 45, to: baseTime)!, count: 3),
            TestEventData.jawClenchEvent(at: baseTime, count: 1),
            TestEventData.jawClenchEvent(at: Calendar.current.date(byAdding: .minute, value: 30, to: baseTime)!, count: 2),
        ]

        let histogram = OvernightReportCalculator.eventHistogram(events: events, bucketMinutes: 15)

        // Should be sorted by time
        for i in 1..<histogram.count {
            XCTAssertTrue(histogram[i].time > histogram[i-1].time)
        }
    }

    func testHistogram_CustomBucketSize() {
        let baseTime = TestEventData.date(year: 2026, month: 2, day: 1, hour: 2, minute: 0)

        let events = [
            TestEventData.jawClenchEvent(at: baseTime, count: 1),                                                  // 2:00
            TestEventData.jawClenchEvent(at: Calendar.current.date(byAdding: .minute, value: 15, to: baseTime)!, count: 2), // 2:15
            TestEventData.jawClenchEvent(at: Calendar.current.date(byAdding: .minute, value: 35, to: baseTime)!, count: 3), // 2:35
        ]

        // With 30-minute buckets: 2:00 and 2:15 -> bucket at 2:00, 2:35 -> bucket at 2:30
        let histogram = OvernightReportCalculator.eventHistogram(events: events, bucketMinutes: 30)

        XCTAssertEqual(histogram.count, 2)
        XCTAssertEqual(histogram[0].count, 2) // 2:00 bucket has 2 events (2:00 and 2:15)
        XCTAssertEqual(histogram[1].count, 1) // 2:30 bucket has 1 event (2:35)
    }
}
