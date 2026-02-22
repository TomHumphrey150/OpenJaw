import Foundation

struct MuseHeadband: Equatable, Sendable {
    let id: String
    let name: String
}

enum MuseFitGuidance: String, Equatable, Sendable, Codable {
    case good
    case adjustHeadband
    case insufficientSignal

    var guidanceText: String? {
        switch self {
        case .good:
            return nil
        case .adjustHeadband:
            return "Fit guidance: adjust the headband for better skin contact before the next session."
        case .insufficientSignal:
            return "Fit guidance: signal quality is insufficient. Reposition the headband and ensure all sensors contact skin."
        }
    }
}

struct MuseRecordingSummary: Equatable, Sendable {
    let startedAt: Date
    let endedAt: Date
    let microArousalCount: Double
    let confidence: Double
    let totalSleepMinutes: Double
    let awakeLikelihood: Double
    let fitGuidance: MuseFitGuidance
    let diagnosticsFileURLs: [URL]

    init(
        startedAt: Date,
        endedAt: Date,
        microArousalCount: Double,
        confidence: Double,
        totalSleepMinutes: Double,
        awakeLikelihood: Double = 0,
        fitGuidance: MuseFitGuidance = .good,
        diagnosticsFileURLs: [URL] = []
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.microArousalCount = microArousalCount
        self.confidence = confidence
        self.totalSleepMinutes = totalSleepMinutes
        self.awakeLikelihood = awakeLikelihood
        self.fitGuidance = fitGuidance
        self.diagnosticsFileURLs = diagnosticsFileURLs
    }

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

    func withDiagnosticsFileURLs(_ fileURLs: [URL]) -> MuseRecordingSummary {
        MuseRecordingSummary(
            startedAt: startedAt,
            endedAt: endedAt,
            microArousalCount: microArousalCount,
            confidence: confidence,
            totalSleepMinutes: totalSleepMinutes,
            awakeLikelihood: awakeLikelihood,
            fitGuidance: fitGuidance,
            diagnosticsFileURLs: fileURLs
        )
    }
}

enum MuseSessionServiceError: Error, Equatable {
    case unavailable
    case noHeadbandFound
    case notConnected
    case needsLicense
    case needsUpdate
    case unsupportedHeadbandModel
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
                totalSleepMinutes: 8 * 60,
                awakeLikelihood: 0.25,
                fitGuidance: .good,
                diagnosticsFileURLs: []
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
