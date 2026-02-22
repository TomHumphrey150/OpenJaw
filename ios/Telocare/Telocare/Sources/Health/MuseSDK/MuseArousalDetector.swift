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

struct MuseSecondDecision: Equatable, Sendable, Codable {
    let secondEpoch: Int64
    let headbandOn: Bool
    let isGoodChannels: [Bool]?
    let hsiPrecisionChannels: [Double]?
    let hasQualityInputs: Bool
    let hasImuInputs: Bool
    let hasOpticsInput: Bool
    let qualityGateSatisfied: Bool
    let blinkDetected: Bool
    let jawClenchDetected: Bool
    let motionSpikeDetected: Bool
    let fitDisturbanceDetected: Bool
    let opticsSpikeDetected: Bool?
    let eventDetected: Bool
    let eventCounted: Bool
    let accelerometerMagnitude: Double?
    let gyroMagnitude: Double?
    let opticsPeakToPeak: Double?
    let awakeEvidence: Double
}

struct MuseDetectionSummary: Equatable, Sendable {
    let microArousalCount: Int
    let validSeconds: Int
    let confidence: Double
    let awakeLikelihood: Double
    let headbandOnCoverage: Double
    let qualityGateCoverage: Double
    let fitGuidance: MuseFitGuidance
    let decisions: [MuseSecondDecision]
}

struct MuseArousalDetector {
    func summarize(framesBySecond: [Int64: MuseSecondFrame]) -> MuseDetectionSummary {
        let sortedFrames = framesBySecond.sorted { $0.key < $1.key }
        guard !sortedFrames.isEmpty else {
            return MuseDetectionSummary(
                microArousalCount: 0,
                validSeconds: 0,
                confidence: 0,
                awakeLikelihood: 0,
                headbandOnCoverage: 0,
                qualityGateCoverage: 0,
                fitGuidance: .insufficientSignal,
                decisions: []
            )
        }

        let totalSeconds = sortedFrames.count
        let sessionHasOptics = sortedFrames.contains { $0.value.opticsPeakToPeak != nil }

        var qualityInputCoverage = 0
        var imuCoverage = 0
        var opticsCoverage = 0
        var headbandOnSeconds = 0
        var validSeconds = 0
        var eventCount = 0
        var awakeEvidenceSum = 0.0
        var awakeEvidenceSeconds = 0
        var lastEventSecond: Int64?
        var decisions: [MuseSecondDecision] = []
        decisions.reserveCapacity(totalSeconds)

        for (second, frame) in sortedFrames {
            let hasQualityInputs = hasQualityInputs(frame)
            if hasQualityInputs {
                qualityInputCoverage += 1
            }

            let hasImuInputs = hasImuInputs(frame)
            if hasImuInputs {
                imuCoverage += 1
            }

            let hasOpticsInput = frame.opticsPeakToPeak != nil
            if hasOpticsInput {
                opticsCoverage += 1
            }

            let headbandOn = frame.headbandOn == true
            if headbandOn {
                headbandOnSeconds += 1
            }

            let qualityGateSatisfied = qualityGate(frame)
            if qualityGateSatisfied {
                validSeconds += 1
            }

            let motionSpikeDetected = motionSpike(frame)
            let fitDisturbanceDetected = fitDisturbance(frame)
            let opticsSpikeDetected: Bool?
            if sessionHasOptics {
                opticsSpikeDetected = (frame.opticsPeakToPeak ?? 0) >= MuseArousalHeuristicConstants.opticsSpikeThresholdMicroamps
            } else {
                opticsSpikeDetected = nil
            }

            let eventDetected = isEvent(
                frame,
                qualityGateSatisfied: qualityGateSatisfied,
                sessionHasOptics: sessionHasOptics
            )

            let eventCounted: Bool
            if eventDetected {
                if let lastEventSecond, second - lastEventSecond < MuseArousalHeuristicConstants.refractoryWindowSeconds {
                    eventCounted = false
                } else {
                    eventCount += 1
                    lastEventSecond = second
                    eventCounted = true
                }
            } else {
                eventCounted = false
            }

            let awakeEvidence = awakeEvidence(frame, qualityGateSatisfied: qualityGateSatisfied)
            if headbandOn {
                awakeEvidenceSum += awakeEvidence
                awakeEvidenceSeconds += 1
            }

            decisions.append(
                MuseSecondDecision(
                    secondEpoch: second,
                    headbandOn: headbandOn,
                    isGoodChannels: frame.isGoodChannels.map { Array($0.prefix(4)) },
                    hsiPrecisionChannels: frame.hsiPrecisionChannels.map { Array($0.prefix(4)) },
                    hasQualityInputs: hasQualityInputs,
                    hasImuInputs: hasImuInputs,
                    hasOpticsInput: hasOpticsInput,
                    qualityGateSatisfied: qualityGateSatisfied,
                    blinkDetected: frame.blinkDetected,
                    jawClenchDetected: frame.jawClenchDetected,
                    motionSpikeDetected: motionSpikeDetected,
                    fitDisturbanceDetected: fitDisturbanceDetected,
                    opticsSpikeDetected: opticsSpikeDetected,
                    eventDetected: eventDetected,
                    eventCounted: eventCounted,
                    accelerometerMagnitude: frame.maxAccelerometerMagnitude,
                    gyroMagnitude: frame.maxGyroMagnitude,
                    opticsPeakToPeak: frame.opticsPeakToPeak,
                    awakeEvidence: awakeEvidence
                )
            )
        }

        let qualityCoverage = Double(validSeconds) / Double(totalSeconds)
        let qualityInputRatio = Double(qualityInputCoverage) / Double(totalSeconds)
        let imuRatio = Double(imuCoverage) / Double(totalSeconds)
        let headbandOnCoverage = Double(headbandOnSeconds) / Double(totalSeconds)
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

        let awakeLikelihood: Double
        if awakeEvidenceSeconds == 0 {
            awakeLikelihood = 0
        } else {
            awakeLikelihood = clamp(
                awakeEvidenceSum / Double(awakeEvidenceSeconds),
                minimum: 0,
                maximum: 1
            )
        }

        let fitGuidance = deriveFitGuidance(
            qualityInputRatio: qualityInputRatio,
            headbandOnCoverage: headbandOnCoverage,
            qualityGateCoverage: qualityCoverage
        )

        return MuseDetectionSummary(
            microArousalCount: eventCount,
            validSeconds: validSeconds,
            confidence: confidence,
            awakeLikelihood: awakeLikelihood,
            headbandOnCoverage: headbandOnCoverage,
            qualityGateCoverage: qualityCoverage,
            fitGuidance: fitGuidance,
            decisions: decisions
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

    private func awakeEvidence(_ frame: MuseSecondFrame, qualityGateSatisfied: Bool) -> Double {
        guard frame.headbandOn == true else {
            return 0
        }

        let motionComponent = motionSpike(frame) ? 0.45 : 0
        let artifactComponent = (frame.blinkDetected || frame.jawClenchDetected) ? 0.30 : 0
        let fitComponent = fitDisturbance(frame) ? 0.20 : 0
        let qualityDropComponent = qualityGateSatisfied ? 0 : 0.05

        return clamp(
            motionComponent + artifactComponent + fitComponent + qualityDropComponent,
            minimum: 0,
            maximum: 1
        )
    }

    private func deriveFitGuidance(
        qualityInputRatio: Double,
        headbandOnCoverage: Double,
        qualityGateCoverage: Double
    ) -> MuseFitGuidance {
        if qualityInputRatio < 0.5 {
            return .insufficientSignal
        }

        if qualityGateCoverage < 0.6 || headbandOnCoverage < 0.8 {
            return .adjustHeadband
        }

        return .good
    }

    private func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        min(maximum, max(minimum, value))
    }
}
