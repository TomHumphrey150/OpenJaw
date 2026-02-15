//
//  TestEventData.swift
//  SkywalkerTests
//
//  Shared test data fixtures for unit tests
//

import Foundation
@testable import Skywalker

/// Test fixtures for jaw clench events and sleep samples
enum TestEventData {

    // MARK: - Date Helpers

    /// Returns a date at a specific hour on the given day
    static func date(year: Int = 2026, month: Int = 2, day: Int = 1, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return Calendar.current.date(from: components)!
    }

    /// Returns today at midnight
    static var todayMidnight: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// Returns yesterday at midnight
    static var yesterdayMidnight: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: todayMidnight)!
    }

    // MARK: - Jaw Clench Events

    /// Creates a jaw clench event at the specified time
    static func jawClenchEvent(at date: Date, count: Int = 1) -> JawClenchEvent {
        JawClenchEvent(id: UUID(), timestamp: date, count: count)
    }

    /// Sample overnight events (from 10 PM to 7 AM)
    static var overnightJawClenchEvents: [JawClenchEvent] {
        let yesterday = yesterdayMidnight

        return [
            // Before sleep (10 PM yesterday)
            jawClenchEvent(at: Calendar.current.date(byAdding: .hour, value: 22, to: yesterday)!, count: 1),
            // During light sleep (11:30 PM)
            jawClenchEvent(at: Calendar.current.date(byAdding: DateComponents(hour: 23, minute: 30), to: yesterday)!, count: 2),
            // During deep sleep (1 AM today)
            jawClenchEvent(at: Calendar.current.date(byAdding: .hour, value: 1, to: todayMidnight)!, count: 3),
            // During REM (3:30 AM)
            jawClenchEvent(at: Calendar.current.date(byAdding: DateComponents(hour: 3, minute: 30), to: todayMidnight)!, count: 4),
            // During light sleep (5 AM)
            jawClenchEvent(at: Calendar.current.date(byAdding: .hour, value: 5, to: todayMidnight)!, count: 5),
            // Waking up (7 AM)
            jawClenchEvent(at: Calendar.current.date(byAdding: .hour, value: 7, to: todayMidnight)!, count: 6),
        ]
    }

    /// Events outside the overnight window (for testing filtering)
    static var outsideWindowEvents: [JawClenchEvent] {
        let yesterday = yesterdayMidnight

        return [
            // Too early (3 PM yesterday - before 6 PM window)
            jawClenchEvent(at: Calendar.current.date(byAdding: .hour, value: 15, to: yesterday)!, count: 1),
            // Too late (2 PM today - after noon cutoff)
            jawClenchEvent(at: Calendar.current.date(byAdding: .hour, value: 14, to: todayMidnight)!, count: 2),
        ]
    }

    // MARK: - Sleep Samples

    /// Creates a sleep sample for the specified phase and time range
    static func sleepSample(phase: HealthKitService.SleepPhase, start: Date, end: Date) -> HealthKitService.SleepSample {
        HealthKitService.SleepSample(startDate: start, endDate: end, phase: phase)
    }

    /// Sample overnight sleep data (typical night)
    static var overnightSleepSamples: [HealthKitService.SleepSample] {
        let yesterday = yesterdayMidnight
        let today = todayMidnight

        return [
            // In bed from 10 PM
            sleepSample(
                phase: .inBed,
                start: Calendar.current.date(byAdding: .hour, value: 22, to: yesterday)!,
                end: Calendar.current.date(byAdding: .hour, value: 7, to: today)!
            ),
            // Awake period (10 PM - 10:30 PM)
            sleepSample(
                phase: .awake,
                start: Calendar.current.date(byAdding: .hour, value: 22, to: yesterday)!,
                end: Calendar.current.date(byAdding: DateComponents(hour: 22, minute: 30), to: yesterday)!
            ),
            // Light/Core sleep (10:30 PM - 12 AM)
            sleepSample(
                phase: .core,
                start: Calendar.current.date(byAdding: DateComponents(hour: 22, minute: 30), to: yesterday)!,
                end: Calendar.current.date(byAdding: .hour, value: 0, to: today)!
            ),
            // Deep sleep (12 AM - 2 AM)
            sleepSample(
                phase: .deep,
                start: Calendar.current.date(byAdding: .hour, value: 0, to: today)!,
                end: Calendar.current.date(byAdding: .hour, value: 2, to: today)!
            ),
            // REM (2 AM - 4 AM)
            sleepSample(
                phase: .rem,
                start: Calendar.current.date(byAdding: .hour, value: 2, to: today)!,
                end: Calendar.current.date(byAdding: .hour, value: 4, to: today)!
            ),
            // Light/Core sleep (4 AM - 6 AM)
            sleepSample(
                phase: .core,
                start: Calendar.current.date(byAdding: .hour, value: 4, to: today)!,
                end: Calendar.current.date(byAdding: .hour, value: 6, to: today)!
            ),
            // Awake (6 AM - 7 AM)
            sleepSample(
                phase: .awake,
                start: Calendar.current.date(byAdding: .hour, value: 6, to: today)!,
                end: Calendar.current.date(byAdding: .hour, value: 7, to: today)!
            ),
        ]
    }

    /// Sleep samples with only awake/inBed (no actual sleep phases)
    static var noSleepSamples: [HealthKitService.SleepSample] {
        let yesterday = yesterdayMidnight
        let today = todayMidnight

        return [
            sleepSample(
                phase: .inBed,
                start: Calendar.current.date(byAdding: .hour, value: 22, to: yesterday)!,
                end: Calendar.current.date(byAdding: .hour, value: 7, to: today)!
            ),
            sleepSample(
                phase: .awake,
                start: Calendar.current.date(byAdding: .hour, value: 22, to: yesterday)!,
                end: Calendar.current.date(byAdding: .hour, value: 7, to: today)!
            ),
        ]
    }

    /// Empty sleep samples array
    static var emptySleepSamples: [HealthKitService.SleepSample] {
        []
    }

    // MARK: - Events for Histogram Testing

    /// Events clustered in same 15-minute bucket
    static var clusteredEvents: [JawClenchEvent] {
        let baseTime = Calendar.current.date(byAdding: .hour, value: 2, to: todayMidnight)! // 2 AM

        return [
            jawClenchEvent(at: baseTime, count: 1),
            jawClenchEvent(at: Calendar.current.date(byAdding: .minute, value: 5, to: baseTime)!, count: 2),
            jawClenchEvent(at: Calendar.current.date(byAdding: .minute, value: 10, to: baseTime)!, count: 3),
        ]
    }

    /// Events spread across multiple 15-minute buckets
    static var spreadEvents: [JawClenchEvent] {
        let baseTime = Calendar.current.date(byAdding: .hour, value: 2, to: todayMidnight)! // 2 AM

        return [
            jawClenchEvent(at: baseTime, count: 1),                                                           // 2:00
            jawClenchEvent(at: Calendar.current.date(byAdding: .minute, value: 15, to: baseTime)!, count: 2), // 2:15
            jawClenchEvent(at: Calendar.current.date(byAdding: .minute, value: 30, to: baseTime)!, count: 3), // 2:30
            jawClenchEvent(at: Calendar.current.date(byAdding: .minute, value: 45, to: baseTime)!, count: 4), // 2:45
        ]
    }
}
