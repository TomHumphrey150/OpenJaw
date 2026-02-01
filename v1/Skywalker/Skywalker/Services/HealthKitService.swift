//
//  HealthKitService.swift
//  Skywalker
//
//  Bruxism Biofeedback - HealthKit sleep data integration
//

import Foundation
import HealthKit
import Observation

@Observable
@MainActor
class HealthKitService {
    private let healthStore = HKHealthStore()

    var sleepSamples: [SleepSample] = []
    var isAuthorized = false
    var authorizationError: String?

    // MARK: - Sleep Data Model

    struct SleepSample: Identifiable {
        let id = UUID()
        let startDate: Date
        let endDate: Date
        let phase: SleepPhase

        var duration: TimeInterval {
            endDate.timeIntervalSince(startDate)
        }
    }

    enum SleepPhase: String, CaseIterable {
        case inBed = "In Bed"
        case awake = "Awake"
        case core = "Core"
        case deep = "Deep"
        case rem = "REM"
        case asleepUnspecified = "Asleep"

        var color: String {
            switch self {
            case .inBed: return "gray"
            case .awake: return "red"
            case .core: return "blue"
            case .deep: return "purple"
            case .rem: return "green"
            case .asleepUnspecified: return "blue"
            }
        }

        init(from categoryValue: Int) {
            switch categoryValue {
            case HKCategoryValueSleepAnalysis.inBed.rawValue:
                self = .inBed
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                self = .awake
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                self = .core
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                self = .deep
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                self = .rem
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                self = .asleepUnspecified
            default:
                self = .asleepUnspecified
            }
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationError = "HealthKit is not available on this device"
            print("[HealthKit] Not available on this device")
            return
        }

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            authorizationError = "Sleep analysis type not available"
            print("[HealthKit] Sleep analysis type not available")
            return
        }

        let typesToRead: Set<HKObjectType> = [sleepType]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            isAuthorized = true
            authorizationError = nil
            print("[HealthKit] Authorization granted")
        } catch {
            authorizationError = error.localizedDescription
            print("[HealthKit] Authorization failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Fetch Sleep Data

    /// Fetch sleep data for a specific night (from evening before to morning of the given date)
    func fetchSleepData(for date: Date) async throws -> [SleepSample] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.sleepTypeNotAvailable
        }

        // Calculate the sleep window: 6 PM previous day to 12 PM given day
        let calendar = Calendar.current
        let morningOfDate = calendar.startOfDay(for: date)

        // Start from 6 PM the evening before
        guard let eveningBefore = calendar.date(byAdding: .hour, value: -6, to: morningOfDate) else {
            throw HealthKitError.dateCalculationFailed
        }

        // End at noon on the given date
        guard let noonOfDate = calendar.date(byAdding: .hour, value: 12, to: morningOfDate) else {
            throw HealthKitError.dateCalculationFailed
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: eveningBefore,
            end: noonOfDate,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let categorySamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }

                let sleepSamples = categorySamples.map { sample in
                    SleepSample(
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        phase: SleepPhase(from: sample.value)
                    )
                }

                continuation.resume(returning: sleepSamples)
            }

            healthStore.execute(query)
        }
    }

    /// Fetch sleep data for last night (convenience method)
    func fetchLastNightSleep() async throws -> [SleepSample] {
        let samples = try await fetchSleepData(for: Date())
        sleepSamples = samples
        print("[HealthKit] Fetched \(samples.count) sleep samples")
        return samples
    }

    // MARK: - Sleep Statistics

    struct SleepStatistics {
        let totalInBed: TimeInterval
        let totalAsleep: TimeInterval
        let totalAwake: TimeInterval
        let totalCore: TimeInterval
        let totalDeep: TimeInterval
        let totalREM: TimeInterval

        var sleepEfficiency: Double {
            guard totalInBed > 0 else { return 0 }
            return totalAsleep / totalInBed * 100
        }
    }

    func calculateStatistics(from samples: [SleepSample]) -> SleepStatistics {
        var totalInBed: TimeInterval = 0
        var totalAsleep: TimeInterval = 0
        var totalAwake: TimeInterval = 0
        var totalCore: TimeInterval = 0
        var totalDeep: TimeInterval = 0
        var totalREM: TimeInterval = 0

        for sample in samples {
            let duration = sample.duration

            switch sample.phase {
            case .inBed:
                totalInBed += duration
            case .awake:
                totalAwake += duration
            case .core:
                totalCore += duration
                totalAsleep += duration
            case .deep:
                totalDeep += duration
                totalAsleep += duration
            case .rem:
                totalREM += duration
                totalAsleep += duration
            case .asleepUnspecified:
                totalAsleep += duration
            }
        }

        return SleepStatistics(
            totalInBed: totalInBed,
            totalAsleep: totalAsleep,
            totalAwake: totalAwake,
            totalCore: totalCore,
            totalDeep: totalDeep,
            totalREM: totalREM
        )
    }

    // MARK: - Error Types

    enum HealthKitError: LocalizedError {
        case sleepTypeNotAvailable
        case dateCalculationFailed
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .sleepTypeNotAvailable:
                return "Sleep analysis type is not available"
            case .dateCalculationFailed:
                return "Failed to calculate date range"
            case .notAuthorized:
                return "HealthKit authorization not granted"
            }
        }
    }
}
