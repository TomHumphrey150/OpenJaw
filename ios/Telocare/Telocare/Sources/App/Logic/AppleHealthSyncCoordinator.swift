import Foundation

protocol AppleHealthSyncCoordinator {
    func referenceLabel(for config: AppleHealthConfig) -> String?
    func fetchReferenceValue(
        config: AppleHealthConfig,
        unit: DoseUnit,
        now: Date
    ) async -> Double?
    func successResult(
        existingConnection: AppleHealthConnection?,
        healthValue: Double?,
        referenceValue: Double?,
        at now: Date
    ) -> AppleHealthSyncResult
    func failureResult(
        existingConnection: AppleHealthConnection?,
        error: Error,
        at now: Date
    ) -> AppleHealthSyncResult
}

struct AppleHealthSyncResult {
    let status: AppleHealthSyncStatus
    let connection: AppleHealthConnection
    let healthValue: Double?
    let referenceValue: Double?
}

struct DefaultAppleHealthSyncCoordinator: AppleHealthSyncCoordinator {
    private let appleHealthDoseService: AppleHealthDoseService

    init(appleHealthDoseService: AppleHealthDoseService) {
        self.appleHealthDoseService = appleHealthDoseService
    }

    func referenceLabel(for config: AppleHealthConfig) -> String? {
        guard config.identifier == .moderateWorkoutMinutes else {
            return nil
        }

        return "Apple Exercise ring minutes (reference)"
    }

    func fetchReferenceValue(
        config: AppleHealthConfig,
        unit: DoseUnit,
        now: Date
    ) async -> Double? {
        guard config.identifier == .moderateWorkoutMinutes else {
            return nil
        }

        let referenceConfig = AppleHealthConfig(
            identifier: .appleExerciseTime,
            aggregation: .cumulativeSum,
            dayAttribution: config.dayAttribution
        )

        do {
            let value = try await appleHealthDoseService.fetchTodayValue(
                for: referenceConfig,
                unit: unit,
                now: now
            )
            guard let value else {
                return nil
            }

            return max(0, value)
        } catch {
            return nil
        }
    }

    func successResult(
        existingConnection: AppleHealthConnection?,
        healthValue: Double?,
        referenceValue: Double?,
        at now: Date
    ) -> AppleHealthSyncResult {
        let status: AppleHealthSyncStatus = healthValue == nil ? .noData : .synced
        let syncTimestamp = DateKeying.timestamp(from: now)
        let connection = AppleHealthConnection(
            isConnected: true,
            connectedAt: existingConnection?.connectedAt ?? syncTimestamp,
            lastSyncAt: syncTimestamp,
            lastSyncStatus: status,
            lastErrorCode: nil
        )

        return AppleHealthSyncResult(
            status: status,
            connection: connection,
            healthValue: healthValue,
            referenceValue: referenceValue
        )
    }

    func failureResult(
        existingConnection: AppleHealthConnection?,
        error: Error,
        at now: Date
    ) -> AppleHealthSyncResult {
        let syncTimestamp = DateKeying.timestamp(from: now)
        let connection = AppleHealthConnection(
            isConnected: true,
            connectedAt: existingConnection?.connectedAt ?? syncTimestamp,
            lastSyncAt: syncTimestamp,
            lastSyncStatus: .failed,
            lastErrorCode: errorCode(for: error)
        )

        return AppleHealthSyncResult(
            status: .failed,
            connection: connection,
            healthValue: nil,
            referenceValue: nil
        )
    }

    private func errorCode(for error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
    }
}
