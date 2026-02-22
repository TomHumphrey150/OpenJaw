import Foundation

protocol AppleHealthDoseService: Sendable {
    func isHealthDataAvailable() -> Bool
    func requestReadAuthorization(for configs: [AppleHealthConfig]) async throws
    func fetchTodayValue(for config: AppleHealthConfig, unit: DoseUnit, now: Date) async throws -> Double?
}

enum AppleHealthDoseServiceError: Error {
    case healthDataUnavailable
    case unsupportedConfiguration
    case unsupportedUnit
    case unsupportedType
}
