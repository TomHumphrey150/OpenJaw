import Foundation

struct MockAppleHealthDoseService: AppleHealthDoseService {
    let available: Bool
    let requestAuthorization: @Sendable ([AppleHealthConfig]) async throws -> Void
    let fetchValue: @Sendable (AppleHealthConfig, DoseUnit, Date) async throws -> Double?

    init(
        available: Bool = true,
        requestAuthorization: @escaping @Sendable ([AppleHealthConfig]) async throws -> Void = { _ in },
        fetchValue: @escaping @Sendable (AppleHealthConfig, DoseUnit, Date) async throws -> Double? = { _, _, _ in nil }
    ) {
        self.available = available
        self.requestAuthorization = requestAuthorization
        self.fetchValue = fetchValue
    }

    func isHealthDataAvailable() -> Bool {
        available
    }

    func requestReadAuthorization(for configs: [AppleHealthConfig]) async throws {
        try await requestAuthorization(configs)
    }

    func fetchTodayValue(for config: AppleHealthConfig, unit: DoseUnit, now: Date) async throws -> Double? {
        try await fetchValue(config, unit, now)
    }
}
