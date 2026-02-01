//
//  OvernightReportCalculator.swift
//  Skywalker
//
//  Testable calculation logic extracted from OvernightReportView
//

import Foundation

/// Pure functions for calculating overnight report metrics
struct OvernightReportCalculator {

    // MARK: - Event Filtering

    /// Filter events to overnight window (6 PM previous day to noon of given date)
    static func filterEventsToOvernightWindow(
        events: [JawClenchEvent],
        forDate date: Date
    ) -> [JawClenchEvent] {
        let calendar = Calendar.current
        let morningOfDate = calendar.startOfDay(for: date)

        guard let eveningBefore = calendar.date(byAdding: .hour, value: -6, to: morningOfDate),
              let noonOfDate = calendar.date(byAdding: .hour, value: 12, to: morningOfDate) else {
            return []
        }

        return events.filter { event in
            event.timestamp >= eveningBefore && event.timestamp <= noonOfDate
        }
    }

    /// Filter events to only those during actual sleep phases (excludes awake and inBed)
    static func filterToSleepPhases(
        events: [JawClenchEvent],
        sleepSamples: [HealthKitService.SleepSample]
    ) -> [JawClenchEvent] {
        let sleepPeriods = sleepSamples.filter { sample in
            sample.phase != .awake && sample.phase != .inBed
        }

        return events.filter { event in
            sleepPeriods.contains { period in
                event.timestamp >= period.startDate && event.timestamp <= period.endDate
            }
        }
    }

    // MARK: - Metrics Calculation

    /// Calculate events per hour of sleep
    static func eventsPerHour(eventCount: Int, totalSleepSeconds: TimeInterval) -> Double {
        let totalHours = totalSleepSeconds / 3600.0
        guard totalHours > 0 else { return 0 }
        return Double(eventCount) / totalHours
    }

    /// Count events by sleep phase
    static func eventsByPhase(
        events: [JawClenchEvent],
        sleepSamples: [HealthKitService.SleepSample]
    ) -> [HealthKitService.SleepPhase: Int] {
        var counts: [HealthKitService.SleepPhase: Int] = [:]

        for event in events {
            // Find which sleep phase this event falls into
            let phase = sleepSamples.first { sample in
                event.timestamp >= sample.startDate && event.timestamp <= sample.endDate
            }?.phase ?? .awake

            counts[phase, default: 0] += 1
        }

        return counts
    }

    /// Create histogram of events in time buckets
    static func eventHistogram(
        events: [JawClenchEvent],
        bucketMinutes: Int = 15
    ) -> [(time: Date, count: Int)] {
        let calendar = Calendar.current
        var buckets: [Date: Int] = [:]

        for event in events {
            // Round down to nearest bucket by constructing a new date with truncated minutes
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: event.timestamp)
            let minute = (components.minute ?? 0) / bucketMinutes * bucketMinutes
            components.minute = minute
            components.second = 0

            if let bucketDate = calendar.date(from: components) {
                buckets[bucketDate, default: 0] += 1
            }
        }

        return buckets.map { (time: $0.key, count: $0.value) }.sorted { $0.time < $1.time }
    }
}
