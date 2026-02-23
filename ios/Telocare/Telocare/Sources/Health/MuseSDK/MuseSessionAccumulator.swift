import Foundation

private struct MuseSecondAggregation {
    var headbandOn: Bool?
    var blinkDetected = false
    var jawClenchDetected = false
    var isGoodChannels: [Bool]?
    var hsiPrecisionChannels: [Double]?
    var maxAccelerometerMagnitude: Double?
    var maxGyroMagnitude: Double?
    var opticsMin: Double?
    var opticsMax: Double?
    var eegChannels: [Double]?

    mutating func recordOptics(_ channels: [Double]) {
        guard !channels.isEmpty else {
            return
        }

        let average = channels.reduce(0, +) / Double(channels.count)
        if let opticsMin {
            self.opticsMin = min(opticsMin, average)
        } else {
            opticsMin = average
        }

        if let opticsMax {
            self.opticsMax = max(opticsMax, average)
        } else {
            opticsMax = average
        }
    }

    var frame: MuseSecondFrame {
        let opticsPeakToPeak: Double?
        if let opticsMin, let opticsMax {
            opticsPeakToPeak = max(0, opticsMax - opticsMin)
        } else {
            opticsPeakToPeak = nil
        }

        return MuseSecondFrame(
            headbandOn: headbandOn,
            blinkDetected: blinkDetected,
            jawClenchDetected: jawClenchDetected,
            isGoodChannels: isGoodChannels,
            hsiPrecisionChannels: hsiPrecisionChannels,
            maxAccelerometerMagnitude: maxAccelerometerMagnitude,
            maxGyroMagnitude: maxGyroMagnitude,
            opticsPeakToPeak: opticsPeakToPeak,
            eegChannels: eegChannels
        )
    }
}

struct MuseAccumulatorSummary: Sendable {
    let recordingSummary: MuseRecordingSummary
    let detectionSummary: MuseDetectionSummary
}

struct MuseSessionAccumulator: Sendable {
    private var framesBySecond: [Int64: MuseSecondAggregation] = [:]

    mutating func reset() {
        framesBySecond.removeAll(keepingCapacity: true)
    }

    mutating func ingest(_ packet: MusePacket) {
        let second = packet.timestampUs / 1_000_000
        var aggregation = framesBySecond[second] ?? MuseSecondAggregation()

        switch packet {
        case .isGood(_, let channels):
            aggregation.isGoodChannels = Array(channels.prefix(4))
        case .hsiPrecision(_, let channels):
            aggregation.hsiPrecisionChannels = Array(channels.prefix(4))
        case .accelerometer(_, let x, let y, let z):
            let magnitude = sqrt(x * x + y * y + z * z)
            if let existing = aggregation.maxAccelerometerMagnitude {
                aggregation.maxAccelerometerMagnitude = max(existing, magnitude)
            } else {
                aggregation.maxAccelerometerMagnitude = magnitude
            }
        case .gyro(_, let x, let y, let z):
            let magnitude = sqrt(x * x + y * y + z * z)
            if let existing = aggregation.maxGyroMagnitude {
                aggregation.maxGyroMagnitude = max(existing, magnitude)
            } else {
                aggregation.maxGyroMagnitude = magnitude
            }
        case .optics(_, let channels):
            aggregation.recordOptics(channels)
        case .eeg(_, let channels):
            aggregation.eegChannels = channels
        case .artifact(_, let headbandOn, let blink, let jawClench):
            if let existing = aggregation.headbandOn {
                aggregation.headbandOn = existing && headbandOn
            } else {
                aggregation.headbandOn = headbandOn
            }
            aggregation.blinkDetected = aggregation.blinkDetected || blink
            aggregation.jawClenchDetected = aggregation.jawClenchDetected || jawClench
        }

        framesBySecond[second] = aggregation
    }

    func detectionSummary(
        detector: MuseArousalDetector = MuseArousalDetector(),
        includeDecisions: Bool = false
    ) -> MuseDetectionSummary {
        let frames = framesBySecond.mapValues(\.frame)
        return detector.summarize(framesBySecond: frames, includeDecisions: includeDecisions)
    }

    func buildSummary(
        startedAt: Date,
        endedAt: Date,
        detector: MuseArousalDetector = MuseArousalDetector(),
        onDecision: ((MuseSecondDecision) -> Void)? = nil
    ) -> MuseAccumulatorSummary {
        let detectionSummary = detectionSummary(detector: detector, includeDecisions: true)
        for decision in detectionSummary.decisions {
            onDecision?(decision)
        }

        let recordingSummary = MuseRecordingSummary(
            startedAt: startedAt,
            endedAt: endedAt,
            microArousalCount: Double(detectionSummary.microArousalCount),
            confidence: detectionSummary.confidence,
            totalSleepMinutes: Double(detectionSummary.validSeconds) / 60.0,
            awakeLikelihood: detectionSummary.awakeLikelihood,
            fitGuidance: detectionSummary.fitGuidance,
            diagnosticsFileURLs: []
        )

        return MuseAccumulatorSummary(
            recordingSummary: recordingSummary,
            detectionSummary: detectionSummary
        )
    }
}
