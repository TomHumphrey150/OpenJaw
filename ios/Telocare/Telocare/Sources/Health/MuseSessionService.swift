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

enum MuseEegSensor: Int, CaseIterable, Equatable, Sendable, Codable {
    case eeg1
    case eeg2
    case eeg3
    case eeg4

    var displayName: String {
        switch self {
        case .eeg1:
            return "EEG1"
        case .eeg2:
            return "EEG2"
        case .eeg3:
            return "EEG3"
        case .eeg4:
            return "EEG4"
        }
    }

    var locationText: String {
        switch self {
        case .eeg1:
            return "Left ear"
        case .eeg2:
            return "Left forehead"
        case .eeg3:
            return "Right forehead"
        case .eeg4:
            return "Right ear"
        }
    }
}

struct MuseSensorFitStatus: Equatable, Sendable, Codable {
    let sensor: MuseEegSensor
    let isGood: Bool?
    let hsiPrecision: Double?
    let passesIsGood: Bool
    let passesHsi: Bool
}

enum MuseFitReadinessBlocker: String, Equatable, Sendable, Codable {
    case noRecentPackets
    case headbandOff
    case missingQualityInputs
    case insufficientGoodChannels
    case poorHsiPrecision
    case lowHeadbandCoverage
    case lowQualityCoverage

    var displayText: String {
        switch self {
        case .noRecentPackets:
            return "No recent Muse packets are arriving."
        case .headbandOff:
            return "Headband-on detection is off."
        case .missingQualityInputs:
            return "Quality inputs are missing."
        case .insufficientGoodChannels:
            return "Not enough channels are marked good."
        case .poorHsiPrecision:
            return "HSI precision indicates poor contact on too many sensors."
        case .lowHeadbandCoverage:
            return "Headband-on coverage is below threshold."
        case .lowQualityCoverage:
            return "Quality-gate coverage is below threshold."
        }
    }
}

struct MuseFitReadinessSnapshot: Equatable, Sendable, Codable {
    let isReady: Bool
    let primaryBlocker: MuseFitReadinessBlocker?
    let blockers: [MuseFitReadinessBlocker]
    let goodChannelCount: Int
    let hsiGoodChannelCount: Int

    static func unknown() -> MuseFitReadinessSnapshot {
        MuseFitReadinessSnapshot(
            isReady: false,
            primaryBlocker: nil,
            blockers: [],
            goodChannelCount: 0,
            hsiGoodChannelCount: 0
        )
    }
}

struct MuseDroppedPacketTypeCount: Equatable, Sendable, Codable {
    let code: Int
    let label: String
    let count: Int
}

struct MuseDroppedPacketTypeCatalog: Sendable {
    private static let knownLabels: [Int: String] = [
        0: "accelerometer",
        1: "gyro",
        2: "eeg",
        23: "is_good",
        25: "hsi_precision",
        29: "is_good",
        31: "hsi_precision",
        41: "optics"
    ]

    static func label(for code: Int) -> String {
        knownLabels[code] ?? "type_\(code)"
    }

    static func counts(from typeCounts: [Int: Int]) -> [MuseDroppedPacketTypeCount] {
        typeCounts
            .map { code, count in
                MuseDroppedPacketTypeCount(code: code, label: label(for: code), count: count)
            }
            .sorted {
                if $0.count == $1.count {
                    return $0.code < $1.code
                }
                return $0.count > $1.count
            }
    }
}

struct MuseSetupPassRates: Equatable, Sendable, Codable {
    let receivingPackets: Double
    let headbandCoverage: Double
    let hsiGood3: Double
    let eegGood3: Double
    let qualityGate: Double

    static let zero = MuseSetupPassRates(
        receivingPackets: 0,
        headbandCoverage: 0,
        hsiGood3: 0,
        eegGood3: 0,
        qualityGate: 0
    )
}

struct MuseSetupArtifactRates: Equatable, Sendable, Codable {
    let blinkTrueRate: Double
    let jawClenchTrueRate: Double

    static let zero = MuseSetupArtifactRates(
        blinkTrueRate: 0,
        jawClenchTrueRate: 0
    )
}

enum MuseSetupDiagnosis: String, Equatable, Sendable, Codable {
    case contactOrArtifact
    case contactOrDrySkin
    case transportUnstable
    case mixedContactAndTransport
    case unknown

    var displayText: String {
        switch self {
        case .contactOrArtifact:
            return "Contact and artifact issue"
        case .contactOrDrySkin:
            return "Likely contact or dry skin issue"
        case .transportUnstable:
            return "Transport issue"
        case .mixedContactAndTransport:
            return "Mixed contact and transport issue"
        case .unknown:
            return "Unknown"
        }
    }

    var rationaleText: String {
        switch self {
        case .contactOrArtifact:
            return "Connection is stable, but EEG quality remains poor and artifact indicators are high."
        case .contactOrDrySkin:
            return "Connection is stable, but EEG quality remains poor despite acceptable HSI fit."
        case .transportUnstable:
            return "Packet continuity or timeout/disconnect events indicate unstable transport."
        case .mixedContactAndTransport:
            return "Both contact-quality and transport-warning signals are present."
        case .unknown:
            return "Not enough evidence yet to classify the setup issue."
        }
    }
}

enum MuseRecordingReliability: String, Equatable, Sendable, Codable {
    case verifiedFit
    case limitedFit
    case insufficientSignal

    var displayText: String {
        switch self {
        case .verifiedFit:
            return "verified fit"
        case .limitedFit:
            return "limited fit"
        case .insufficientSignal:
            return "insufficient signal"
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
    let startedWithFitOverride: Bool
    let recordingReliability: MuseRecordingReliability
    let diagnosticsFileURLs: [URL]

    init(
        startedAt: Date,
        endedAt: Date,
        microArousalCount: Double,
        confidence: Double,
        totalSleepMinutes: Double,
        awakeLikelihood: Double = 0,
        fitGuidance: MuseFitGuidance = .good,
        startedWithFitOverride: Bool = false,
        recordingReliability: MuseRecordingReliability? = nil,
        diagnosticsFileURLs: [URL] = []
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.microArousalCount = microArousalCount
        self.confidence = confidence
        self.totalSleepMinutes = totalSleepMinutes
        self.awakeLikelihood = awakeLikelihood
        self.fitGuidance = fitGuidance
        self.startedWithFitOverride = startedWithFitOverride
        self.recordingReliability = recordingReliability
            ?? Self.defaultReliability(fitGuidance: fitGuidance, startedWithFitOverride: startedWithFitOverride)
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
            startedWithFitOverride: startedWithFitOverride,
            recordingReliability: recordingReliability,
            diagnosticsFileURLs: fileURLs
        )
    }

    func withFitRecordingContext(
        startedWithFitOverride: Bool,
        recordingReliability: MuseRecordingReliability
    ) -> MuseRecordingSummary {
        MuseRecordingSummary(
            startedAt: startedAt,
            endedAt: endedAt,
            microArousalCount: microArousalCount,
            confidence: confidence,
            totalSleepMinutes: totalSleepMinutes,
            awakeLikelihood: awakeLikelihood,
            fitGuidance: fitGuidance,
            startedWithFitOverride: startedWithFitOverride,
            recordingReliability: recordingReliability,
            diagnosticsFileURLs: diagnosticsFileURLs
        )
    }

    private static func defaultReliability(
        fitGuidance: MuseFitGuidance,
        startedWithFitOverride: Bool
    ) -> MuseRecordingReliability {
        if fitGuidance == .insufficientSignal {
            return .insufficientSignal
        }

        if startedWithFitOverride || fitGuidance == .adjustHeadband {
            return .limitedFit
        }

        return .verifiedFit
    }
}

struct MuseLiveDiagnostics: Equatable, Sendable {
    let elapsedSeconds: Int
    let signalConfidence: Double
    let awakeLikelihood: Double
    let headbandOnCoverage: Double
    let qualityGateCoverage: Double
    let fitGuidance: MuseFitGuidance
    let rawDataPacketCount: Int
    let rawArtifactPacketCount: Int
    let parsedPacketCount: Int
    let droppedPacketCount: Int
    let droppedPacketTypes: [MuseDroppedPacketTypeCount]
    let fitReadiness: MuseFitReadinessSnapshot
    let sensorStatuses: [MuseSensorFitStatus]
    let lastPacketAgeSeconds: Double?
    let setupDiagnosis: MuseSetupDiagnosis
    let windowPassRates: MuseSetupPassRates
    let artifactRates: MuseSetupArtifactRates
    let sdkWarningCounts: [MuseDroppedPacketTypeCount]
    let latestHeadbandOn: Bool?
    let latestHasQualityInputs: Bool?

    init(
        elapsedSeconds: Int,
        signalConfidence: Double,
        awakeLikelihood: Double,
        headbandOnCoverage: Double,
        qualityGateCoverage: Double,
        fitGuidance: MuseFitGuidance,
        rawDataPacketCount: Int,
        rawArtifactPacketCount: Int,
        parsedPacketCount: Int,
        droppedPacketCount: Int,
        droppedDataPacketTypeCounts: [Int: Int],
        lastPacketAgeSeconds: Double?,
        fitReadiness: MuseFitReadinessSnapshot = .unknown(),
        sensorStatuses: [MuseSensorFitStatus] = [],
        droppedPacketTypes: [MuseDroppedPacketTypeCount]? = nil,
        setupDiagnosis: MuseSetupDiagnosis = .unknown,
        windowPassRates: MuseSetupPassRates = .zero,
        artifactRates: MuseSetupArtifactRates = .zero,
        sdkWarningCounts: [MuseDroppedPacketTypeCount]? = nil,
        latestHeadbandOn: Bool? = nil,
        latestHasQualityInputs: Bool? = nil
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.signalConfidence = signalConfidence
        self.awakeLikelihood = awakeLikelihood
        self.headbandOnCoverage = headbandOnCoverage
        self.qualityGateCoverage = qualityGateCoverage
        self.fitGuidance = fitGuidance
        self.rawDataPacketCount = rawDataPacketCount
        self.rawArtifactPacketCount = rawArtifactPacketCount
        self.parsedPacketCount = parsedPacketCount
        self.droppedPacketCount = droppedPacketCount
        self.droppedPacketTypes = droppedPacketTypes
            ?? MuseDroppedPacketTypeCatalog.counts(from: droppedDataPacketTypeCounts)
        self.fitReadiness = fitReadiness
        self.sensorStatuses = sensorStatuses
        self.lastPacketAgeSeconds = lastPacketAgeSeconds
        self.setupDiagnosis = setupDiagnosis
        self.windowPassRates = windowPassRates
        self.artifactRates = artifactRates
        self.sdkWarningCounts = sdkWarningCounts ?? []
        self.latestHeadbandOn = latestHeadbandOn
        self.latestHasQualityInputs = latestHasQualityInputs
    }

    var isReceivingData: Bool {
        guard let lastPacketAgeSeconds else {
            return false
        }

        return lastPacketAgeSeconds <= 3
    }

    var droppedDataPacketTypeCounts: [Int: Int] {
        droppedPacketTypes.reduce(into: [:]) { result, item in
            result[item.code] = item.count
        }
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
    func fitDiagnostics(at now: Date) async -> MuseLiveDiagnostics?
    func recordingDiagnostics(at now: Date) async -> MuseLiveDiagnostics?
    func snapshotSetupDiagnostics(at now: Date) async -> [URL]
    func latestSetupDiagnosticsFileURLs() async -> [URL]
}

private actor MockMuseSessionDiagnosticsState {
    private var setupDiagnosticsFileURLs: [URL] = []

    func ensureSetupDiagnosticsFileURLs(at now: Date) -> [URL] {
        if setupDiagnosticsFileURLs.isEmpty {
            setupDiagnosticsFileURLs = [mockSetupDiagnosticsURL(at: now)]
        }

        return setupDiagnosticsFileURLs
    }

    func latestSetupDiagnosticsFileURLs() -> [URL] {
        setupDiagnosticsFileURLs
    }
}

private func mockSetupDiagnosticsURL(at now: Date) -> URL {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let timestamp = formatter.string(from: now)
    return URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mock-muse-setup-\(timestamp).txt")
}

struct MockMuseSessionService: MuseSessionService {
    let scan: @Sendable () async throws -> [MuseHeadband]
    let connectHeadband: @Sendable (MuseHeadband, Data?) async throws -> Void
    let disconnectHeadband: @Sendable () async -> Void
    let startSession: @Sendable (Date) async throws -> Void
    let stopSession: @Sendable (Date) async throws -> MuseRecordingSummary
    let fitDiagnosticsSnapshot: @Sendable (Date) async -> MuseLiveDiagnostics?
    let recordingDiagnosticsSnapshot: @Sendable (Date) async -> MuseLiveDiagnostics?
    let snapshotSetupDiagnosticsCapture: @Sendable (Date) async -> [URL]
    let latestSetupDiagnosticsCapture: @Sendable () async -> [URL]

    init(
        scan: (@Sendable () async throws -> [MuseHeadband])? = nil,
        connectHeadband: (@Sendable (MuseHeadband, Data?) async throws -> Void)? = nil,
        disconnectHeadband: (@Sendable () async -> Void)? = nil,
        startSession: (@Sendable (Date) async throws -> Void)? = nil,
        stopSession: (@Sendable (Date) async throws -> MuseRecordingSummary)? = nil,
        fitDiagnosticsSnapshot: (@Sendable (Date) async -> MuseLiveDiagnostics?)? = nil,
        recordingDiagnosticsSnapshot: (@Sendable (Date) async -> MuseLiveDiagnostics?)? = nil,
        snapshotSetupDiagnosticsCapture: (@Sendable (Date) async -> [URL])? = nil,
        latestSetupDiagnosticsCapture: (@Sendable () async -> [URL])? = nil
    ) {
        let diagnosticsState = MockMuseSessionDiagnosticsState()
        self.scan = scan ?? {
            [
                MuseHeadband(
                    id: "mock-muse-athena",
                    name: "Mock Muse S Athena"
                )
            ]
        }
        self.connectHeadband = connectHeadband ?? { _, _ in
            _ = await diagnosticsState.ensureSetupDiagnosticsFileURLs(at: Date())
        }
        self.disconnectHeadband = disconnectHeadband ?? {}
        self.startSession = startSession ?? { startDate in
            _ = await diagnosticsState.ensureSetupDiagnosticsFileURLs(at: startDate)
        }
        self.stopSession = stopSession ?? { endDate in
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
        self.fitDiagnosticsSnapshot = fitDiagnosticsSnapshot ?? { _ in nil }
        self.recordingDiagnosticsSnapshot = recordingDiagnosticsSnapshot ?? { _ in nil }
        self.snapshotSetupDiagnosticsCapture = snapshotSetupDiagnosticsCapture ?? { now in
            await diagnosticsState.ensureSetupDiagnosticsFileURLs(at: now)
        }
        self.latestSetupDiagnosticsCapture = latestSetupDiagnosticsCapture ?? {
            await diagnosticsState.latestSetupDiagnosticsFileURLs()
        }
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

    func fitDiagnostics(at now: Date) async -> MuseLiveDiagnostics? {
        await fitDiagnosticsSnapshot(now)
    }

    func recordingDiagnostics(at now: Date) async -> MuseLiveDiagnostics? {
        await recordingDiagnosticsSnapshot(now)
    }

    func snapshotSetupDiagnostics(at now: Date) async -> [URL] {
        await snapshotSetupDiagnosticsCapture(now)
    }

    func latestSetupDiagnosticsFileURLs() async -> [URL] {
        await latestSetupDiagnosticsCapture()
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

    func fitDiagnostics(at now: Date) async -> MuseLiveDiagnostics? {
        _ = now
        return nil
    }

    func recordingDiagnostics(at now: Date) async -> MuseLiveDiagnostics? {
        _ = now
        return nil
    }

    func snapshotSetupDiagnostics(at now: Date) async -> [URL] {
        _ = now
        return []
    }

    func latestSetupDiagnosticsFileURLs() async -> [URL] {
        []
    }
}
