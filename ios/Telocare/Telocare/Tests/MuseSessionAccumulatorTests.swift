import Foundation
import Testing
@testable import Telocare

struct MuseSessionAccumulatorTests {
    @Test func summaryUsesQualityGatedSecondsForSleepMinutes() {
        var accumulator = MuseSessionAccumulator()

        accumulator.ingest(
            .artifact(timestampUs: 1_000_000, headbandOn: true, blink: true, jawClench: false)
        )
        accumulator.ingest(
            .isGood(timestampUs: 1_000_000, channels: [true, true, true, true])
        )
        accumulator.ingest(
            .hsiPrecision(timestampUs: 1_000_000, channels: [1, 1, 1, 1])
        )
        accumulator.ingest(
            .accelerometer(timestampUs: 1_000_000, x: 0.2, y: 0.0, z: 0.0)
        )
        accumulator.ingest(
            .gyro(timestampUs: 1_000_000, x: 20, y: 0, z: 0)
        )

        accumulator.ingest(
            .artifact(timestampUs: 2_000_000, headbandOn: true, blink: false, jawClench: false)
        )
        accumulator.ingest(
            .isGood(timestampUs: 2_000_000, channels: [true, false, false, true])
        )
        accumulator.ingest(
            .hsiPrecision(timestampUs: 2_000_000, channels: [4, 4, 4, 4])
        )

        let summary = accumulator.buildSummary(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 120)
        ).recordingSummary

        #expect(summary.totalSleepMinutes == (1.0 / 60.0))
        #expect(summary.microArousalCount == 1)
        #expect(summary.microArousalRatePerHour == 3600)
        #expect(summary.awakeLikelihood > 0)
        #expect(summary.fitGuidance == .adjustHeadband)
    }

    @Test func resetClearsAllAccumulatedData() {
        var accumulator = MuseSessionAccumulator()

        accumulator.ingest(
            .artifact(timestampUs: 1_000_000, headbandOn: true, blink: true, jawClench: false)
        )
        accumulator.ingest(
            .isGood(timestampUs: 1_000_000, channels: [true, true, true, true])
        )
        accumulator.ingest(
            .hsiPrecision(timestampUs: 1_000_000, channels: [1, 1, 1, 1])
        )
        accumulator.reset()

        let summary = accumulator.buildSummary(startedAt: Date(), endedAt: Date()).recordingSummary

        #expect(summary.microArousalCount == 0)
        #expect(summary.totalSleepMinutes == 0)
        #expect(summary.confidence == 0)
        #expect(summary.fitGuidance == .insufficientSignal)
    }

    @Test func buildSummaryEmitsPerSecondDecisions() {
        var accumulator = MuseSessionAccumulator()
        accumulator.ingest(
            .artifact(timestampUs: 1_000_000, headbandOn: true, blink: false, jawClench: false)
        )
        accumulator.ingest(
            .isGood(timestampUs: 1_000_000, channels: [true, true, true, true])
        )
        accumulator.ingest(
            .hsiPrecision(timestampUs: 1_000_000, channels: [1, 1, 1, 1])
        )
        accumulator.ingest(
            .accelerometer(timestampUs: 1_000_000, x: 0.01, y: 0, z: 0)
        )
        accumulator.ingest(
            .gyro(timestampUs: 1_000_000, x: 1, y: 0, z: 0)
        )

        var decisionCount = 0
        let summary = accumulator.buildSummary(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 60),
            onDecision: { _ in
                decisionCount += 1
            }
        )

        #expect(decisionCount == 1)
        #expect(summary.detectionSummary.decisions.count == 1)
        #expect(summary.recordingSummary.fitGuidance == .good)
    }

    @Test func rollingRetentionPrunesOldCalibrationFrames() {
        var accumulator = MuseSessionAccumulator(retentionWindowSeconds: 30)

        for second in 0..<35 {
            let timestampUs = Int64(second) * 1_000_000
            accumulator.ingest(
                .artifact(timestampUs: timestampUs, headbandOn: true, blink: false, jawClench: false)
            )
            accumulator.ingest(
                .isGood(timestampUs: timestampUs, channels: [true, true, true, true])
            )
            accumulator.ingest(
                .hsiPrecision(timestampUs: timestampUs, channels: [1, 1, 1, 1])
            )
        }

        let detectionSummary = accumulator.detectionSummary(includeDecisions: true)

        #expect(detectionSummary.decisions.count == 30)
        #expect(detectionSummary.decisions.first?.secondEpoch == 5)
        #expect(detectionSummary.decisions.last?.secondEpoch == 34)
    }
}
