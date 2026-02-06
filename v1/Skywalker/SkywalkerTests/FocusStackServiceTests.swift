//
//  FocusStackServiceTests.swift
//  SkywalkerTests
//
//  Tests for capacity filtering and time-of-day detection
//

import Foundation
import Testing
@testable import Skywalker

struct FocusStackServiceTests {

    // MARK: - Capacity Filtering Tests (using EnergyLevel directly)

    @Test func energyLevel_numericValues() {
        // Test that energy levels have correct numeric values for comparison
        #expect(EnergyLevel.low.numericValue == 1)
        #expect(EnergyLevel.medium.numericValue == 2)
        #expect(EnergyLevel.high.numericValue == 3)
    }

    @Test func energyLevel_isWithin() {
        // Low energy tasks fit all energy levels
        #expect(EnergyLevel.low.isWithin(max: .low) == true)
        #expect(EnergyLevel.low.isWithin(max: .medium) == true)
        #expect(EnergyLevel.low.isWithin(max: .high) == true)

        // Medium energy tasks fit medium and high
        #expect(EnergyLevel.medium.isWithin(max: .low) == false)
        #expect(EnergyLevel.medium.isWithin(max: .medium) == true)
        #expect(EnergyLevel.medium.isWithin(max: .high) == true)

        // High energy tasks only fit high
        #expect(EnergyLevel.high.isWithin(max: .low) == false)
        #expect(EnergyLevel.high.isWithin(max: .medium) == false)
        #expect(EnergyLevel.high.isWithin(max: .high) == true)
    }

    @Test func userCapacity_timeOptions() {
        // Verify time options are correct
        #expect(UserCapacity.timeOptions == [5, 10, 15, 30, 60])
    }

    @Test func userCapacity_timeDisplayText() {
        #expect(UserCapacity.timeDisplayText(minutes: 5) == "5")
        #expect(UserCapacity.timeDisplayText(minutes: 30) == "30")
        #expect(UserCapacity.timeDisplayText(minutes: 60) == "60+")
        #expect(UserCapacity.timeDisplayText(minutes: 120) == "60+")
    }

    // MARK: - Time of Day Detection Tests

    @Test func timeOfDay_morning() {
        // Hours 5-11 should return morning
        for hour in 5..<12 {
            let date = createDate(hour: hour)
            let section = TimeOfDaySection.currentSection(now: date)
            #expect(section == .morning, "Hour \(hour) should be morning")
        }
    }

    @Test func timeOfDay_afternoon() {
        // Hours 12-16 should return afternoon
        for hour in 12..<17 {
            let date = createDate(hour: hour)
            let section = TimeOfDaySection.currentSection(now: date)
            #expect(section == .afternoon, "Hour \(hour) should be afternoon")
        }
    }

    @Test func timeOfDay_evening() {
        // Hours 17-20 should return evening
        for hour in 17..<21 {
            let date = createDate(hour: hour)
            let section = TimeOfDaySection.currentSection(now: date)
            #expect(section == .evening, "Hour \(hour) should be evening")
        }
    }

    @Test func timeOfDay_preBed_evening() {
        // Hours 21-23 should return preBed
        for hour in 21..<24 {
            let date = createDate(hour: hour)
            let section = TimeOfDaySection.currentSection(now: date)
            #expect(section == .preBed, "Hour \(hour) should be preBed")
        }
    }

    @Test func timeOfDay_preBed_lateNight() {
        // Hours 0-4 (after midnight) should return preBed
        for hour in 0..<5 {
            let date = createDate(hour: hour)
            let section = TimeOfDaySection.currentSection(now: date)
            #expect(section == .preBed, "Hour \(hour) should be preBed (late night)")
        }
    }

    @Test func timeOfDay_2337_isPreBed() {
        // Specific test case: 23:37 should be preBed, not morning
        let date = createDate(hour: 23, minute: 37)
        let section = TimeOfDaySection.currentSection(now: date)
        #expect(section == .preBed, "23:37 should be preBed")
    }

    @Test func timeOfDay_0300_isPreBed() {
        // 3am should also be preBed
        let date = createDate(hour: 3, minute: 0)
        let section = TimeOfDaySection.currentSection(now: date)
        #expect(section == .preBed, "3:00 AM should be preBed")
    }

    // MARK: - DateInterval Tests (midnight wrap)

    @Test func dateInterval_morning_sameDay() {
        let day = createDate(hour: 12, minute: 0)
        let interval = TimeOfDaySection.morning.dateInterval(on: day)
        #expect(interval != nil)
        if let interval = interval {
            let calendar = Calendar.current
            let startHour = calendar.component(.hour, from: interval.start)
            let endHour = calendar.component(.hour, from: interval.end)
            #expect(startHour == 5, "Morning should start at 5am")
            #expect(endHour == 12, "Morning should end at 12pm")
            #expect(interval.end > interval.start, "End must be after start")
        }
    }

    @Test func dateInterval_preBed_crossesMidnight() {
        // preBed is 21:00 to 05:00 next day - must handle midnight wrap
        let day = createDate(hour: 22, minute: 0)
        let interval = TimeOfDaySection.preBed.dateInterval(on: day)
        #expect(interval != nil, "preBed interval should not be nil")
        if let interval = interval {
            let calendar = Calendar.current
            let startHour = calendar.component(.hour, from: interval.start)
            let endHour = calendar.component(.hour, from: interval.end)
            let startDay = calendar.component(.day, from: interval.start)
            let endDay = calendar.component(.day, from: interval.end)
            #expect(startHour == 21, "preBed should start at 9pm")
            #expect(endHour == 5, "preBed should end at 5am")
            #expect(endDay == startDay + 1, "preBed end should be next day")
            #expect(interval.end > interval.start, "End must be after start (critical: no crash)")
        }
    }

    // MARK: - Helpers

    private func createDate(hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 5
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }
}
