import Foundation
import HealthKit

struct HealthKitAppleHealthDoseService: AppleHealthDoseService {
    private let healthStore: HKHealthStore
    private let moderateHeartRateThresholdBPM = 100.0

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func isHealthDataAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestReadAuthorization(for configs: [AppleHealthConfig]) async throws {
        guard isHealthDataAvailable() else {
            throw AppleHealthDoseServiceError.healthDataUnavailable
        }

        let readTypes = Set(configs.flatMap(readObjectTypes(for:)))
        if readTypes.isEmpty {
            return
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    func fetchTodayValue(for config: AppleHealthConfig, unit: DoseUnit, now: Date) async throws -> Double? {
        guard isHealthDataAvailable() else {
            throw AppleHealthDoseServiceError.healthDataUnavailable
        }

        if config.identifier == .moderateWorkoutMinutes {
            return try await fetchModerateWorkoutMinutes(for: config, unit: unit, now: now)
        }

        switch config.aggregation {
        case .cumulativeSum:
            return try await fetchCumulativeQuantity(for: config, unit: unit, now: now)
        case .durationSum:
            return try await fetchCategoryDuration(for: config, unit: unit, now: now)
        case .sleepAsleepDurationSum:
            return try await fetchSleepDuration(for: config, unit: unit, now: now)
        }
    }

    private func fetchModerateWorkoutMinutes(
        for config: AppleHealthConfig,
        unit: DoseUnit,
        now: Date
    ) async throws -> Double? {
        let interval = dateInterval(for: config.dayAttribution, now: now)
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: Int(HKObjectQueryNoLimit)
        )
        let workouts = try await descriptor.result(for: healthStore)
        if workouts.isEmpty {
            return nil
        }

        var totalMinutes = 0.0
        for workout in workouts {
            let workoutInterval = DateInterval(start: workout.startDate, end: workout.endDate)
            guard let clippedInterval = overlap(of: workoutInterval, with: interval) else {
                continue
            }

            let workoutMinutes = clippedInterval.duration / 60.0
            guard workoutMinutes > 0 else {
                continue
            }

            if isModerateWorkoutType(workout.workoutActivityType) {
                totalMinutes += workoutMinutes
                continue
            }

            guard let averageHeartRateBPM = workoutAverageHeartRateBPM(workout) else {
                continue
            }

            if averageHeartRateBPM >= moderateHeartRateThresholdBPM {
                totalMinutes += workoutMinutes
            }
        }

        let converted: Double
        switch unit {
        case .minutes:
            converted = totalMinutes
        case .hours:
            converted = totalMinutes / 60.0
        case .milliliters, .reps, .breaths:
            throw AppleHealthDoseServiceError.unsupportedUnit
        }

        if converted <= 0 {
            return nil
        }

        return converted
    }

    private func fetchCumulativeQuantity(
        for config: AppleHealthConfig,
        unit: DoseUnit,
        now: Date
    ) async throws -> Double? {
        guard let quantityType = quantityType(for: config.identifier) else {
            throw AppleHealthDoseServiceError.unsupportedType
        }

        let interval = dateInterval(for: config.dayAttribution, now: now)
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: .strictStartDate
        )
        let samplePredicate = HKSamplePredicate.quantitySample(type: quantityType, predicate: predicate)
        let descriptor = HKStatisticsQueryDescriptor(predicate: samplePredicate, options: .cumulativeSum)
        let statistics = try await descriptor.result(for: healthStore)
        guard let quantity = statistics?.sumQuantity() else {
            return nil
        }

        guard let hkUnit = quantityUnit(for: unit) else {
            throw AppleHealthDoseServiceError.unsupportedUnit
        }

        let value = quantity.doubleValue(for: hkUnit)
        if value <= 0 {
            return nil
        }

        return value
    }

    private func fetchCategoryDuration(
        for config: AppleHealthConfig,
        unit: DoseUnit,
        now: Date
    ) async throws -> Double? {
        guard let categoryType = categoryType(for: config.identifier) else {
            throw AppleHealthDoseServiceError.unsupportedType
        }

        let interval = dateInterval(for: config.dayAttribution, now: now)
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: categoryType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: Int(HKObjectQueryNoLimit)
        )
        let samples = try await descriptor.result(for: healthStore)
        let durations = samples.map { DateInterval(start: $0.startDate, end: $0.endDate).duration }
        let totalDuration = durations.reduce(0, +)
        let converted = convertDuration(seconds: totalDuration, to: unit)
        if converted <= 0 {
            return nil
        }

        return converted
    }

    private func fetchSleepDuration(
        for config: AppleHealthConfig,
        unit: DoseUnit,
        now: Date
    ) async throws -> Double? {
        guard config.identifier == .sleepAnalysis else {
            throw AppleHealthDoseServiceError.unsupportedConfiguration
        }

        guard let categoryType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw AppleHealthDoseServiceError.unsupportedType
        }

        let interval = dateInterval(for: config.dayAttribution, now: now)
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: categoryType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: Int(HKObjectQueryNoLimit)
        )
        let samples = try await descriptor.result(for: healthStore)
        let asleepValues = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let asleepIntervals = samples
            .filter { asleepValues.contains($0.value) }
            .compactMap { overlap(of: DateInterval(start: $0.startDate, end: $0.endDate), with: interval) }
        let mergedIntervals = mergeIntervals(asleepIntervals)
        let seconds = mergedIntervals.map(\.duration).reduce(0, +)
        let converted = convertDuration(seconds: seconds, to: unit)
        if converted <= 0 {
            return nil
        }

        return converted
    }

    private func readObjectTypes(for config: AppleHealthConfig) -> [HKObjectType] {
        switch config.identifier {
        case .moderateWorkoutMinutes:
            var types: [HKObjectType] = [HKObjectType.workoutType()]
            if let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) {
                types.append(heartRateType)
            }
            if let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
                types.append(exerciseType)
            }
            return types

        case .appleExerciseTime, .dietaryWater:
            if let type = quantityType(for: config.identifier) {
                return [type]
            }
            return []

        case .mindfulSession, .sleepAnalysis:
            if let type = categoryType(for: config.identifier) {
                return [type]
            }
            return []
        }
    }

    private func quantityType(for identifier: AppleHealthIdentifier) -> HKQuantityType? {
        switch identifier {
        case .appleExerciseTime:
            return HKObjectType.quantityType(forIdentifier: .appleExerciseTime)
        case .dietaryWater:
            return HKObjectType.quantityType(forIdentifier: .dietaryWater)
        case .moderateWorkoutMinutes, .sleepAnalysis, .mindfulSession:
            return nil
        }
    }

    private func categoryType(for identifier: AppleHealthIdentifier) -> HKCategoryType? {
        switch identifier {
        case .mindfulSession:
            return HKObjectType.categoryType(forIdentifier: .mindfulSession)
        case .sleepAnalysis:
            return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .appleExerciseTime, .moderateWorkoutMinutes, .dietaryWater:
            return nil
        }
    }

    private func isModerateWorkoutType(_ workoutType: HKWorkoutActivityType) -> Bool {
        switch workoutType {
        case .walking, .hiking, .mindAndBody, .preparationAndRecovery, .flexibility, .cooldown, .other:
            return false
        default:
            return true
        }
    }

    private func workoutAverageHeartRateBPM(_ workout: HKWorkout) -> Double? {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }

        guard let averageQuantity = workout.statistics(for: heartRateType)?.averageQuantity() else {
            return nil
        }

        let beatsPerMinute = HKUnit.count().unitDivided(by: HKUnit.minute())
        return averageQuantity.doubleValue(for: beatsPerMinute)
    }

    private func quantityUnit(for unit: DoseUnit) -> HKUnit? {
        switch unit {
        case .minutes:
            return .minute()
        case .hours:
            return .hour()
        case .milliliters:
            return HKUnit.literUnit(with: .milli)
        case .reps, .breaths:
            return nil
        }
    }

    private func convertDuration(seconds: TimeInterval, to unit: DoseUnit) -> Double {
        switch unit {
        case .minutes:
            return seconds / 60.0
        case .hours:
            return seconds / 3600.0
        case .milliliters, .reps, .breaths:
            return 0
        }
    }

    private func dateInterval(for attribution: AppleHealthDayAttribution, now: Date) -> DateInterval {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        switch attribution {
        case .localDay:
            let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
            return DateInterval(start: startOfToday, end: endOfToday)

        case .previousNightNoonCutoff:
            let noonToday = calendar.date(byAdding: .hour, value: 12, to: startOfToday) ?? now
            let noonYesterday = calendar.date(byAdding: .day, value: -1, to: noonToday) ?? noonToday
            return DateInterval(start: noonYesterday, end: noonToday)
        }
    }

    private func overlap(of lhs: DateInterval, with rhs: DateInterval) -> DateInterval? {
        let start = max(lhs.start, rhs.start)
        let end = min(lhs.end, rhs.end)
        if start >= end {
            return nil
        }

        return DateInterval(start: start, end: end)
    }

    private func mergeIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        if sorted.isEmpty {
            return []
        }

        var merged: [DateInterval] = []
        var current = sorted[0]

        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                let end = max(current.end, interval.end)
                current = DateInterval(start: current.start, end: end)
                continue
            }

            merged.append(current)
            current = interval
        }

        merged.append(current)
        return merged
    }
}
