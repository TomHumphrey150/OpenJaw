//
//  HealthKitServiceTests.swift
//  SkywalkerTests
//
//  Unit tests for HealthKitService sleep phase mapping and statistics
//

import XCTest
import HealthKit
@testable import Skywalker

final class HealthKitServiceTests: XCTestCase {

    // MARK: - SleepPhase Mapping Tests

    func testSleepPhaseFromInBed() {
        let phase = HealthKitService.SleepPhase(from: HKCategoryValueSleepAnalysis.inBed.rawValue)
        XCTAssertEqual(phase, .inBed)
    }

    func testSleepPhaseFromAwake() {
        let phase = HealthKitService.SleepPhase(from: HKCategoryValueSleepAnalysis.awake.rawValue)
        XCTAssertEqual(phase, .awake)
    }

    func testSleepPhaseFromAsleepCore() {
        let phase = HealthKitService.SleepPhase(from: HKCategoryValueSleepAnalysis.asleepCore.rawValue)
        XCTAssertEqual(phase, .core)
    }

    func testSleepPhaseFromAsleepDeep() {
        let phase = HealthKitService.SleepPhase(from: HKCategoryValueSleepAnalysis.asleepDeep.rawValue)
        XCTAssertEqual(phase, .deep)
    }

    func testSleepPhaseFromAsleepREM() {
        let phase = HealthKitService.SleepPhase(from: HKCategoryValueSleepAnalysis.asleepREM.rawValue)
        XCTAssertEqual(phase, .rem)
    }

    func testSleepPhaseFromAsleepUnspecified() {
        let phase = HealthKitService.SleepPhase(from: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue)
        XCTAssertEqual(phase, .asleepUnspecified)
    }

    func testSleepPhaseFromUnknown() {
        // Unknown/invalid values should default to asleepUnspecified
        let phase = HealthKitService.SleepPhase(from: 999)
        XCTAssertEqual(phase, .asleepUnspecified)
    }

    // MARK: - SleepSample Duration Tests

    func testSleepSampleDuration() {
        let start = Date()
        let end = start.addingTimeInterval(3600) // 1 hour later

        let sample = HealthKitService.SleepSample(startDate: start, endDate: end, phase: .core)

        XCTAssertEqual(sample.duration, 3600, accuracy: 0.001)
    }

    func testSleepSampleDurationZero() {
        let date = Date()
        let sample = HealthKitService.SleepSample(startDate: date, endDate: date, phase: .awake)

        XCTAssertEqual(sample.duration, 0, accuracy: 0.001)
    }

    // MARK: - Calculate Statistics Tests

    func testCalculateStatistics_TotalAsleep() async {
        let service = await HealthKitService()
        let now = Date()

        let samples = [
            HealthKitService.SleepSample(
                startDate: now,
                endDate: now.addingTimeInterval(7200), // 2 hours
                phase: .core
            ),
            HealthKitService.SleepSample(
                startDate: now.addingTimeInterval(7200),
                endDate: now.addingTimeInterval(10800), // 1 hour
                phase: .deep
            ),
            HealthKitService.SleepSample(
                startDate: now.addingTimeInterval(10800),
                endDate: now.addingTimeInterval(14400), // 1 hour
                phase: .rem
            ),
        ]

        let stats = await service.calculateStatistics(from: samples)

        // Total asleep = core + deep + REM = 2 + 1 + 1 = 4 hours
        XCTAssertEqual(stats.totalAsleep, 14400, accuracy: 0.001) // 4 hours in seconds
        XCTAssertEqual(stats.totalCore, 7200, accuracy: 0.001)    // 2 hours
        XCTAssertEqual(stats.totalDeep, 3600, accuracy: 0.001)    // 1 hour
        XCTAssertEqual(stats.totalREM, 3600, accuracy: 0.001)     // 1 hour
    }

    func testCalculateStatistics_SleepEfficiency() async {
        let service = await HealthKitService()
        let now = Date()

        let samples = [
            // In bed for 8 hours
            HealthKitService.SleepSample(
                startDate: now,
                endDate: now.addingTimeInterval(28800),
                phase: .inBed
            ),
            // Awake for 1 hour
            HealthKitService.SleepSample(
                startDate: now,
                endDate: now.addingTimeInterval(3600),
                phase: .awake
            ),
            // Asleep for 7 hours (core sleep)
            HealthKitService.SleepSample(
                startDate: now.addingTimeInterval(3600),
                endDate: now.addingTimeInterval(28800),
                phase: .core
            ),
        ]

        let stats = await service.calculateStatistics(from: samples)

        // Sleep efficiency = (asleep / inBed) * 100 = (7/8) * 100 = 87.5%
        XCTAssertEqual(stats.totalInBed, 28800, accuracy: 0.001)  // 8 hours
        XCTAssertEqual(stats.totalAsleep, 25200, accuracy: 0.001) // 7 hours
        XCTAssertEqual(stats.totalAwake, 3600, accuracy: 0.001)   // 1 hour
        XCTAssertEqual(stats.sleepEfficiency, 87.5, accuracy: 0.1)
    }

    func testCalculateStatistics_Empty() async {
        let service = await HealthKitService()

        let stats = await service.calculateStatistics(from: [])

        XCTAssertEqual(stats.totalInBed, 0)
        XCTAssertEqual(stats.totalAsleep, 0)
        XCTAssertEqual(stats.totalAwake, 0)
        XCTAssertEqual(stats.totalCore, 0)
        XCTAssertEqual(stats.totalDeep, 0)
        XCTAssertEqual(stats.totalREM, 0)
        XCTAssertEqual(stats.sleepEfficiency, 0)
    }

    func testCalculateStatistics_AsleepUnspecified() async {
        let service = await HealthKitService()
        let now = Date()

        let samples = [
            HealthKitService.SleepSample(
                startDate: now,
                endDate: now.addingTimeInterval(3600), // 1 hour
                phase: .asleepUnspecified
            ),
        ]

        let stats = await service.calculateStatistics(from: samples)

        // asleepUnspecified should count toward totalAsleep
        XCTAssertEqual(stats.totalAsleep, 3600, accuracy: 0.001)
    }

    // MARK: - SleepPhase Color Tests

    func testSleepPhaseColors() {
        // Verify all phases have a color defined
        for phase in HealthKitService.SleepPhase.allCases {
            XCTAssertFalse(phase.color.isEmpty, "Phase \(phase) should have a color")
        }
    }
}
