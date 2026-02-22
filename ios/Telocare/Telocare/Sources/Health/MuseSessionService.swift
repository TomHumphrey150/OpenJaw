import Foundation

struct MuseHeadband: Equatable, Sendable {
    let id: String
    let name: String
}

struct MuseRecordingSummary: Equatable, Sendable {
    let startedAt: Date
    let endedAt: Date
    let microArousalCount: Double
    let confidence: Double
    let totalSleepMinutes: Double

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }

    var microArousalRatePerHour: Double? {
        let hours = totalSleepMinutes / 60.0
        guard hours > 0 else {
            return nil
        }

        return microArousalCount / hours
    }
}

enum MuseSessionServiceError: Error, Equatable {
    case unavailable
    case noHeadbandFound
    case notConnected
    case needsLicense
    case needsUpdate
    case alreadyRecording
    case notRecording
}

protocol MuseSessionService: Sendable {
    func scanForHeadbands() async throws -> [MuseHeadband]
    func connect(to headband: MuseHeadband, licenseData: Data?) async throws
    func disconnect() async
    func startRecording(at startDate: Date) async throws
    func stopRecording(at endDate: Date) async throws -> MuseRecordingSummary
}

struct MockMuseSessionService: MuseSessionService {
    let scan: @Sendable () async throws -> [MuseHeadband]
    let connectHeadband: @Sendable (MuseHeadband, Data?) async throws -> Void
    let disconnectHeadband: @Sendable () async -> Void
    let startSession: @Sendable (Date) async throws -> Void
    let stopSession: @Sendable (Date) async throws -> MuseRecordingSummary

    init(
        scan: @escaping @Sendable () async throws -> [MuseHeadband] = {
            [
                MuseHeadband(
                    id: "mock-muse-athena",
                    name: "Mock Muse S Athena"
                )
            ]
        },
        connectHeadband: @escaping @Sendable (MuseHeadband, Data?) async throws -> Void = { _, _ in },
        disconnectHeadband: @escaping @Sendable () async -> Void = {},
        startSession: @escaping @Sendable (Date) async throws -> Void = { _ in },
        stopSession: @escaping @Sendable (Date) async throws -> MuseRecordingSummary = { endDate in
            MuseRecordingSummary(
                startedAt: endDate.addingTimeInterval(-8 * 60 * 60),
                endedAt: endDate,
                microArousalCount: 12,
                confidence: 0.72,
                totalSleepMinutes: 8 * 60
            )
        }
    ) {
        self.scan = scan
        self.connectHeadband = connectHeadband
        self.disconnectHeadband = disconnectHeadband
        self.startSession = startSession
        self.stopSession = stopSession
    }

    func scanForHeadbands() async throws -> [MuseHeadband] {
        try await scan()
    }

    func connect(to headband: MuseHeadband, licenseData: Data?) async throws {
        try await connectHeadband(headband, licenseData)
    }

    func disconnect() async {
        await disconnectHeadband()
    }

    func startRecording(at startDate: Date) async throws {
        try await startSession(startDate)
    }

    func stopRecording(at endDate: Date) async throws -> MuseRecordingSummary {
        try await stopSession(endDate)
    }
}

struct UnavailableMuseSessionService: MuseSessionService {
    func scanForHeadbands() async throws -> [MuseHeadband] {
        throw MuseSessionServiceError.unavailable
    }

    func connect(to headband: MuseHeadband, licenseData: Data?) async throws {
        _ = headband
        _ = licenseData
        throw MuseSessionServiceError.unavailable
    }

    func disconnect() async {
    }

    func startRecording(at startDate: Date) async throws {
        _ = startDate
        throw MuseSessionServiceError.unavailable
    }

    func stopRecording(at endDate: Date) async throws -> MuseRecordingSummary {
        _ = endDate
        throw MuseSessionServiceError.unavailable
    }
}
