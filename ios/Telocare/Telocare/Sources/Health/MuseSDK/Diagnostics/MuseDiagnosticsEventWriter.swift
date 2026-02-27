import Foundation

struct MuseHeuristicConstantsSnapshot: Codable, Equatable, Sendable {
    let minimumGoodChannels: Int
    let maximumGoodHsiPrecision: Double
    let minimumDisturbedChannels: Int
    let accelerometerMotionThresholdG: Double
    let gyroMotionThresholdDps: Double
    let opticsSpikeThresholdMicroamps: Double
    let refractoryWindowSeconds: Int64
    let maximumConfidence: Double

    static func current() -> MuseHeuristicConstantsSnapshot {
        MuseHeuristicConstantsSnapshot(
            minimumGoodChannels: MuseArousalHeuristicConstants.minimumGoodChannels,
            maximumGoodHsiPrecision: MuseArousalHeuristicConstants.maximumGoodHsiPrecision,
            minimumDisturbedChannels: MuseArousalHeuristicConstants.minimumDisturbedChannels,
            accelerometerMotionThresholdG: MuseArousalHeuristicConstants.accelerometerMotionThresholdG,
            gyroMotionThresholdDps: MuseArousalHeuristicConstants.gyroMotionThresholdDps,
            opticsSpikeThresholdMicroamps: MuseArousalHeuristicConstants.opticsSpikeThresholdMicroamps,
            refractoryWindowSeconds: MuseArousalHeuristicConstants.refractoryWindowSeconds,
            maximumConfidence: MuseArousalHeuristicConstants.maximumConfidence
        )
    }
}

struct MuseDiagnosticsSummaryRecord: Codable, Equatable, Sendable {
    let microArousalCount: Int
    let validSeconds: Int
    let confidence: Double
    let awakeLikelihood: Double
    let headbandOnCoverage: Double
    let qualityGateCoverage: Double
    let fitGuidance: MuseFitGuidance
}

struct MuseDiagnosticsManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let capturePhase: MuseDiagnosticsCapturePhase
    let startedAtISO8601: String
    let endedAtISO8601: String
    let appVersion: String
    let heuristicConstants: MuseHeuristicConstantsSnapshot
    let summary: MuseDiagnosticsSummaryRecord?
    let files: [String]
}

struct MuseDiagnosticsFitSnapshotRecord: Codable, Equatable, Sendable {
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
}

final class MuseDiagnosticsEventWriter {
    static let schemaVersion = 2

    let decisionsFileURL: URL
    let manifestFileURL: URL

    private let encoder: JSONEncoder
    private var fileHandle: FileHandle?
    private let capturePhase: MuseDiagnosticsCapturePhase

    init(
        sessionDirectoryURL: URL,
        capturePhase: MuseDiagnosticsCapturePhase
    ) throws {
        decisionsFileURL = sessionDirectoryURL.appendingPathComponent("decisions.ndjson")
        manifestFileURL = sessionDirectoryURL.appendingPathComponent("manifest.json")
        self.capturePhase = capturePhase

        encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]

        FileManager.default.createFile(atPath: decisionsFileURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: decisionsFileURL)
    }

    deinit {
        close()
    }

    func appendDecision(_ decision: MuseSecondDecision) {
        let line = MuseDiagnosticsDecisionLine(
            type: "second",
            schemaVersion: Self.schemaVersion,
            timestampISO8601: nil,
            message: nil,
            decision: decision,
            summary: nil,
            fitSnapshot: nil
        )
        appendLine(line)
    }

    func appendServiceEvent(_ message: String, at date: Date = Date()) {
        let line = MuseDiagnosticsDecisionLine(
            type: "service_event",
            schemaVersion: Self.schemaVersion,
            timestampISO8601: Self.iso8601Timestamp(from: date),
            message: message,
            decision: nil,
            summary: nil,
            fitSnapshot: nil
        )
        appendLine(line)
    }

    func appendFitSnapshot(_ diagnostics: MuseLiveDiagnostics, at date: Date = Date()) {
        let line = MuseDiagnosticsDecisionLine(
            type: "fit_snapshot",
            schemaVersion: Self.schemaVersion,
            timestampISO8601: Self.iso8601Timestamp(from: date),
            message: nil,
            decision: nil,
            summary: nil,
            fitSnapshot: MuseDiagnosticsFitSnapshotRecord(
                elapsedSeconds: diagnostics.elapsedSeconds,
                signalConfidence: diagnostics.signalConfidence,
                awakeLikelihood: diagnostics.awakeLikelihood,
                headbandOnCoverage: diagnostics.headbandOnCoverage,
                qualityGateCoverage: diagnostics.qualityGateCoverage,
                fitGuidance: diagnostics.fitGuidance,
                rawDataPacketCount: diagnostics.rawDataPacketCount,
                rawArtifactPacketCount: diagnostics.rawArtifactPacketCount,
                parsedPacketCount: diagnostics.parsedPacketCount,
                droppedPacketCount: diagnostics.droppedPacketCount,
                droppedPacketTypes: diagnostics.droppedPacketTypes,
                fitReadiness: diagnostics.fitReadiness,
                sensorStatuses: diagnostics.sensorStatuses,
                lastPacketAgeSeconds: diagnostics.lastPacketAgeSeconds,
                setupDiagnosis: diagnostics.setupDiagnosis,
                windowPassRates: diagnostics.windowPassRates,
                artifactRates: diagnostics.artifactRates,
                sdkWarningCounts: diagnostics.sdkWarningCounts,
                latestHeadbandOn: diagnostics.latestHeadbandOn,
                latestHasQualityInputs: diagnostics.latestHasQualityInputs
            )
        )
        appendLine(line)
    }

    func appendSummary(_ detectionSummary: MuseDetectionSummary) {
        let line = MuseDiagnosticsDecisionLine(
            type: "summary",
            schemaVersion: Self.schemaVersion,
            timestampISO8601: nil,
            message: nil,
            decision: nil,
            summary: MuseDiagnosticsSummaryRecord(
                microArousalCount: detectionSummary.microArousalCount,
                validSeconds: detectionSummary.validSeconds,
                confidence: detectionSummary.confidence,
                awakeLikelihood: detectionSummary.awakeLikelihood,
                headbandOnCoverage: detectionSummary.headbandOnCoverage,
                qualityGateCoverage: detectionSummary.qualityGateCoverage,
                fitGuidance: detectionSummary.fitGuidance
            ),
            fitSnapshot: nil
        )
        appendLine(line)
    }

    func writeManifest(
        startedAt: Date,
        endedAt: Date,
        summary: MuseDetectionSummary?,
        files: [URL]
    ) throws {
        let manifest = MuseDiagnosticsManifest(
            schemaVersion: Self.schemaVersion,
            capturePhase: capturePhase,
            startedAtISO8601: Self.iso8601Timestamp(from: startedAt),
            endedAtISO8601: Self.iso8601Timestamp(from: endedAt),
            appVersion: Self.appVersionDescription(),
            heuristicConstants: .current(),
            summary: summary.map {
                MuseDiagnosticsSummaryRecord(
                    microArousalCount: $0.microArousalCount,
                    validSeconds: $0.validSeconds,
                    confidence: $0.confidence,
                    awakeLikelihood: $0.awakeLikelihood,
                    headbandOnCoverage: $0.headbandOnCoverage,
                    qualityGateCoverage: $0.qualityGateCoverage,
                    fitGuidance: $0.fitGuidance
                )
            },
            files: files.map(\.lastPathComponent)
        )

        let data = try encoder.encode(manifest)
        try data.write(to: manifestFileURL, options: .atomic)
    }

    func close() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    private func appendLine(_ line: MuseDiagnosticsDecisionLine) {
        guard let fileHandle else {
            return
        }

        guard let encodedLine = try? encoder.encode(line) else {
            return
        }

        do {
            try fileHandle.write(contentsOf: encodedLine)
            try fileHandle.write(contentsOf: Data([0x0A]))
        } catch {
            return
        }
    }

    private static func iso8601Timestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func appVersionDescription() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            return "\(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            return version
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return "unknown"
        }
    }
}

private struct MuseDiagnosticsDecisionLine: Codable {
    let type: String
    let schemaVersion: Int
    let timestampISO8601: String?
    let message: String?
    let decision: MuseSecondDecision?
    let summary: MuseDiagnosticsSummaryRecord?
    let fitSnapshot: MuseDiagnosticsFitSnapshotRecord?
}
