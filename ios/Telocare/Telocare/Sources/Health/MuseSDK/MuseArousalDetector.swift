import Foundation

struct MuseSecondFrame: Equatable, Sendable {
    var headbandOn: Bool?
    var blinkDetected: Bool
    var jawClenchDetected: Bool
    var isGoodChannels: [Bool]?
    var hsiPrecisionChannels: [Double]?
    var maxAccelerometerMagnitude: Double?
    var maxGyroMagnitude: Double?
    var opticsPeakToPeak: Double?
    var eegChannels: [Double]?
}

struct MuseDetectionSummary: Equatable, Sendable {
    let microArousalCount: Int
    let validSeconds: Int
    let confidence: Double
}

struct MuseArousalDetector {
    func summarize(framesBySecond: [Int64: MuseSecondFrame]) -> MuseDetectionSummary {
        let sortedFrames = framesBySecond.sorted { $0.key < $1.key }
        guard !sortedFrames.isEmpty else {
            return MuseDetectionSummary(microArousalCount: 0, validSeconds: 0, confidence: 0)
        }

        let totalSeconds = sortedFrames.count
        let sessionHasOptics = sortedFrames.contains { $0.value.opticsPeakToPeak != nil }

        var qualityInputCoverage = 0
        var imuCoverage = 0
        var opticsCoverage = 0
        var validSeconds = 0
        var eventCount = 0
        var lastEventSecond: Int64?

        for (second, frame) in sortedFrames {
            if hasQualityInputs(frame) {
                qualityInputCoverage += 1
            }
            if hasImuInputs(frame) {
                imuCoverage += 1
            }
            if frame.opticsPeakToPeak != nil {
                opticsCoverage += 1
            }

            let qualityGateSatisfied = qualityGate(frame)
            if qualityGateSatisfied {
                validSeconds += 1
            }

            guard isEvent(frame, qualityGateSatisfied: qualityGateSatisfied, sessionHasOptics: sessionHasOptics) else {
                continue
            }

            if let lastEventSecond, second - lastEventSecond < MuseArousalHeuristicConstants.refractoryWindowSeconds {
                continue
            }

            eventCount += 1
            lastEventSecond = second
        }

        let qualityCoverage = Double(validSeconds) / Double(totalSeconds)
        let qualityInputRatio = Double(qualityInputCoverage) / Double(totalSeconds)
        let imuRatio = Double(imuCoverage) / Double(totalSeconds)
        let opticsRatio: Double
        if sessionHasOptics {
            opticsRatio = Double(opticsCoverage) / Double(totalSeconds)
        } else {
            opticsRatio = 1
        }

        let sensorCoverage = qualityInputRatio * 0.5 + imuRatio * 0.3 + opticsRatio * 0.2
        let confidence = clamp(
            qualityCoverage * 0.6 + sensorCoverage * 0.4,
            minimum: 0,
            maximum: MuseArousalHeuristicConstants.maximumConfidence
        )

        return MuseDetectionSummary(
            microArousalCount: eventCount,
            validSeconds: validSeconds,
            confidence: confidence
        )
    }

    private func hasQualityInputs(_ frame: MuseSecondFrame) -> Bool {
        frame.isGoodChannels != nil && frame.hsiPrecisionChannels != nil
    }

    private func hasImuInputs(_ frame: MuseSecondFrame) -> Bool {
        frame.maxAccelerometerMagnitude != nil && frame.maxGyroMagnitude != nil
    }

    private func qualityGate(_ frame: MuseSecondFrame) -> Bool {
        guard frame.headbandOn == true else {
            return false
        }
        guard
            let goodChannels = frame.isGoodChannels,
            let hsiChannels = frame.hsiPrecisionChannels
        else {
            return false
        }

        let goodCount = goodChannels.prefix(4).filter { $0 }.count
        let hsiGoodCount = hsiChannels.prefix(4).filter {
            $0 <= MuseArousalHeuristicConstants.maximumGoodHsiPrecision
        }.count

        return goodCount >= MuseArousalHeuristicConstants.minimumGoodChannels
            && hsiGoodCount >= MuseArousalHeuristicConstants.minimumGoodChannels
    }

    private func isEvent(
        _ frame: MuseSecondFrame,
        qualityGateSatisfied: Bool,
        sessionHasOptics: Bool
    ) -> Bool {
        if qualityGateSatisfied && (frame.blinkDetected || frame.jawClenchDetected) {
            return true
        }

        guard frame.headbandOn == true else {
            return false
        }
        guard motionSpike(frame) else {
            return false
        }
        guard fitDisturbance(frame) else {
            return false
        }

        if sessionHasOptics {
            return (frame.opticsPeakToPeak ?? 0) >= MuseArousalHeuristicConstants.opticsSpikeThresholdMicroamps
        }

        return true
    }

    private func motionSpike(_ frame: MuseSecondFrame) -> Bool {
        let accelerometer = frame.maxAccelerometerMagnitude ?? 0
        let gyro = frame.maxGyroMagnitude ?? 0

        return accelerometer >= MuseArousalHeuristicConstants.accelerometerMotionThresholdG
            || gyro >= MuseArousalHeuristicConstants.gyroMotionThresholdDps
    }

    private func fitDisturbance(_ frame: MuseSecondFrame) -> Bool {
        let badIsGoodChannels: Int
        if let channels = frame.isGoodChannels {
            badIsGoodChannels = channels.prefix(4).filter { !$0 }.count
        } else {
            badIsGoodChannels = 0
        }

        let poorHsiChannels: Int
        if let hsiChannels = frame.hsiPrecisionChannels {
            poorHsiChannels = hsiChannels.prefix(4).filter {
                $0 > MuseArousalHeuristicConstants.maximumGoodHsiPrecision
            }.count
        } else {
            poorHsiChannels = 0
        }

        return badIsGoodChannels >= MuseArousalHeuristicConstants.minimumDisturbedChannels
            || poorHsiChannels >= MuseArousalHeuristicConstants.minimumDisturbedChannels
    }

    private func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        min(maximum, max(minimum, value))
    }
}
