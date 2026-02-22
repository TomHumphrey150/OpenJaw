import Foundation
import Testing
@testable import Telocare

struct MuseDiagnosticsReplayTests {
    @Test func replayingDecisionTraceMatchesSummary() throws {
        let detector = MuseArousalDetector()
        let frames: [Int64: MuseSecondFrame] = [
            1: MuseSecondFrame(
                headbandOn: true,
                blinkDetected: true,
                jawClenchDetected: false,
                isGoodChannels: [true, true, true, true],
                hsiPrecisionChannels: [1, 1, 1, 1],
                maxAccelerometerMagnitude: 0.28,
                maxGyroMagnitude: 17,
                opticsPeakToPeak: nil,
                eegChannels: nil
            ),
            2: MuseSecondFrame(
                headbandOn: true,
                blinkDetected: false,
                jawClenchDetected: false,
                isGoodChannels: [true, false, false, true],
                hsiPrecisionChannels: [4, 4, 4, 4],
                maxAccelerometerMagnitude: 0.05,
                maxGyroMagnitude: 2,
                opticsPeakToPeak: nil,
                eegChannels: nil
            )
        ]

        let summary = detector.summarize(framesBySecond: frames)
        let decisionsFileURL = try writeDecisionTrace(
            decisions: summary.decisions,
            summary: summary
        )

        let replay = try loadDecisionTrace(from: decisionsFileURL)
        var replayFrames: [Int64: MuseSecondFrame] = [:]
        for decision in replay.decisions {
            replayFrames[decision.secondEpoch] = MuseSecondFrame(
                headbandOn: decision.headbandOn,
                blinkDetected: decision.blinkDetected,
                jawClenchDetected: decision.jawClenchDetected,
                isGoodChannels: decision.isGoodChannels,
                hsiPrecisionChannels: decision.hsiPrecisionChannels,
                maxAccelerometerMagnitude: decision.accelerometerMagnitude,
                maxGyroMagnitude: decision.gyroMagnitude,
                opticsPeakToPeak: decision.opticsPeakToPeak,
                eegChannels: nil
            )
        }

        let replaySummary = detector.summarize(framesBySecond: replayFrames)

        #expect(replaySummary.microArousalCount == replay.summary.microArousalCount)
        #expect(replaySummary.validSeconds == replay.summary.validSeconds)
        #expect(replaySummary.fitGuidance == replay.summary.fitGuidance)
        #expect(abs(replaySummary.confidence - replay.summary.confidence) < 0.0001)
        #expect(abs(replaySummary.awakeLikelihood - replay.summary.awakeLikelihood) < 0.0001)
    }

    private func writeDecisionTrace(
        decisions: [MuseSecondDecision],
        summary: MuseDetectionSummary
    ) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("muse-replay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let fileURL = temporaryDirectory.appendingPathComponent("decisions.ndjson")
        var data = Data()
        let encoder = JSONEncoder()

        for decision in decisions {
            let line = ReplayNDJSONLine(
                type: "second",
                schemaVersion: MuseDiagnosticsEventWriter.schemaVersion,
                timestampISO8601: nil,
                message: nil,
                decision: decision,
                summary: nil
            )
            let encoded = try encoder.encode(line)
            data.append(encoded)
            data.append(0x0A)
        }

        let summaryLine = ReplayNDJSONLine(
            type: "summary",
            schemaVersion: MuseDiagnosticsEventWriter.schemaVersion,
            timestampISO8601: nil,
            message: nil,
            decision: nil,
            summary: MuseDiagnosticsSummaryRecord(
                microArousalCount: summary.microArousalCount,
                validSeconds: summary.validSeconds,
                confidence: summary.confidence,
                awakeLikelihood: summary.awakeLikelihood,
                headbandOnCoverage: summary.headbandOnCoverage,
                qualityGateCoverage: summary.qualityGateCoverage,
                fitGuidance: summary.fitGuidance
            )
        )
        let encodedSummary = try encoder.encode(summaryLine)
        data.append(encodedSummary)
        data.append(0x0A)

        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func loadDecisionTrace(from fileURL: URL) throws -> ReplayResult {
        let data = try Data(contentsOf: fileURL)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ReplayError.unreadableContent
        }

        var decisions: [MuseSecondDecision] = []
        var summary: MuseDiagnosticsSummaryRecord?
        let decoder = JSONDecoder()

        for line in content.split(separator: "\n") {
            let lineData = Data(line.utf8)
            let decoded = try decoder.decode(ReplayNDJSONLine.self, from: lineData)
            if decoded.type == "second", let decision = decoded.decision {
                decisions.append(decision)
            }
            if decoded.type == "summary", let decodedSummary = decoded.summary {
                summary = decodedSummary
            }
        }

        guard let summary else {
            throw ReplayError.missingSummary
        }

        return ReplayResult(decisions: decisions, summary: summary)
    }
}

private struct ReplayNDJSONLine: Codable {
    let type: String
    let schemaVersion: Int
    let timestampISO8601: String?
    let message: String?
    let decision: MuseSecondDecision?
    let summary: MuseDiagnosticsSummaryRecord?
}

private struct ReplayResult {
    let decisions: [MuseSecondDecision]
    let summary: MuseDiagnosticsSummaryRecord
}

private enum ReplayError: Error {
    case unreadableContent
    case missingSummary
}
