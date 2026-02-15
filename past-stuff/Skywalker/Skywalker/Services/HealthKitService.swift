//
//  HealthKitService.swift
//  Skywalker
//
//  Bruxism Biofeedback - HealthKit sleep data integration
//

import Foundation
import HealthKit
import Observation

enum HealthHintType: String, CaseIterable {
    case exercise
    case water
    case mindfulness
}

@Observable
@MainActor
class HealthKitService {
    private let healthStore = HKHealthStore()

    var sleepSamples: [SleepSample] = []
    var isAuthorized = false
    var authorizationError: String?
    var authorizedHintTypes: Set<HealthHintType> = []

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

    func requestAuthorization(for hintType: HealthHintType) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationError = "HealthKit is not available on this device"
            print("[HealthKit] Not available on this device")
            return false
        }

        guard let objectType = objectType(for: hintType) else {
            authorizationError = "HealthKit type not available"
            print("[HealthKit] Type not available for \(hintType)")
            return false
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [objectType])
            // Note: authorizationStatus(for:) only reports WRITE permission status.
            // For read-only access, HealthKit doesn't reveal if user granted permission (privacy).
            // We optimistically mark as authorized after request succeeds; actual data fetch
            // will fail if user denied access.
            authorizedHintTypes.insert(hintType)
            print("[HealthKit] Authorization requested for \(hintType) - marked as authorized")
            return true
        } catch {
            authorizationError = error.localizedDescription
            print("[HealthKit] Authorization failed for \(hintType): \(error.localizedDescription)")
            return false
        }
    }

    func isAuthorized(for hintType: HealthHintType) -> Bool {
        // We track authorized types in memory after successful authorization request.
        // Note: authorizationStatus(for:) only works for WRITE permissions, not read-only.
        return authorizedHintTypes.contains(hintType)
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

    // MARK: - Fetch Hint Data

    func fetchWorkoutSummary(in interval: DateInterval) async throws -> (count: Int, minutes: Double) {
        guard isAuthorized(for: .exercise) else {
            throw HealthKitError.notAuthorized
        }
        let workoutType = HKWorkoutType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = samples as? [HKWorkout] ?? []
                let minutes = workouts.reduce(0.0) { total, workout in
                    total + workout.duration / 60.0
                }
                continuation.resume(returning: (workouts.count, minutes))
            }

            healthStore.execute(query)
        }
    }

    func fetchWaterLiters(in interval: DateInterval) async throws -> Double {
        guard isAuthorized(for: .water) else {
            throw HealthKitError.notAuthorized
        }
        guard let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater) else {
            throw HealthKitError.typeNotAvailable
        }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        let unit = HKUnit.liter()

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: waterType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let quantitySamples = samples as? [HKQuantitySample] ?? []
                let total = quantitySamples.reduce(0.0) { sum, sample in
                    sum + sample.quantity.doubleValue(for: unit)
                }
                continuation.resume(returning: total)
            }

            healthStore.execute(query)
        }
    }

    func fetchMindfulMinutes(in interval: DateInterval) async throws -> Double {
        guard isAuthorized(for: .mindfulness) else {
            throw HealthKitError.notAuthorized
        }
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            throw HealthKitError.typeNotAvailable
        }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: mindfulType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let sessions = samples as? [HKCategorySample] ?? []
                let minutes = sessions.reduce(0.0) { total, sample in
                    total + sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                }
                continuation.resume(returning: minutes)
            }

            healthStore.execute(query)
        }
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
        case typeNotAvailable

        var errorDescription: String? {
            switch self {
            case .sleepTypeNotAvailable:
                return "Sleep analysis type is not available"
            case .dateCalculationFailed:
                return "Failed to calculate date range"
            case .notAuthorized:
                return "HealthKit authorization not granted"
            case .typeNotAvailable:
                return "Health data type not available"
            }
        }
    }

    // MARK: - Helpers

    private func objectType(for hintType: HealthHintType) -> HKObjectType? {
        switch hintType {
        case .exercise:
            return HKWorkoutType.workoutType()
        case .water:
            return HKObjectType.quantityType(forIdentifier: .dietaryWater)
        case .mindfulness:
            return HKObjectType.categoryType(forIdentifier: .mindfulSession)
        }
    }
}
