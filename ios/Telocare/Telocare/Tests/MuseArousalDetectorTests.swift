import Foundation
import Testing
@testable import Telocare

struct MuseArousalDetectorTests {
    @Test func qualityGateOnlyCountsValidSeconds() {
        let detector = MuseArousalDetector()
        let frames: [Int64: MuseSecondFrame] = [
            1: frame(
                headbandOn: true,
                isGood: [true, true, true, true],
                hsi: [1, 1, 1, 1],
                blink: false,
                jawClench: false,
                accelerometer: 0.05,
                gyro: 3,
                optics: nil
            ),
            2: frame(
                headbandOn: false,
                isGood: [true, true, true, true],
                hsi: [1, 1, 1, 1],
                blink: true,
                jawClench: false,
                accelerometer: 0.22,
                gyro: 18,
                optics: 12
            )
        ]

        let summary = detector.summarize(framesBySecond: frames)

        #expect(summary.validSeconds == 1)
        #expect(summary.microArousalCount == 0)
    }

    @Test func refractoryWindowDeduplicatesNearbyEvents() {
        let detector = MuseArousalDetector()
        let frames: [Int64: MuseSecondFrame] = [
            10: frame(
                headbandOn: true,
                isGood: [true, true, true, true],
                hsi: [1, 1, 1, 1],
                blink: true,
                jawClench: false,
                accelerometer: 0.2,
                gyro: 18,
                optics: 10
            ),
            25: frame(
                headbandOn: true,
                isGood: [true, true, true, true],
                hsi: [1, 1, 1, 1],
                blink: true,
                jawClench: false,
                accelerometer: 0.2,
                gyro: 18,
                optics: 11
            ),
            40: frame(
                headbandOn: true,
                isGood: [true, true, true, true],
                hsi: [1, 1, 1, 1],
                blink: true,
                jawClench: false,
                accelerometer: 0.2,
                gyro: 18,
                optics: 9
            )
        ]

        let summary = detector.summarize(framesBySecond: frames)

        #expect(summary.microArousalCount == 2)
    }

    @Test func nonArtifactEventRequiresOpticsSpikeWhenSessionIncludesOptics() {
        let detector = MuseArousalDetector()
        let frames: [Int64: MuseSecondFrame] = [
            1: frame(
                headbandOn: true,
                isGood: [true, true, true, true],
                hsi: [1, 1, 4, 4],
                blink: false,
                jawClench: false,
                accelerometer: 0.22,
                gyro: 19,
                optics: 2
            ),
            2: frame(
                headbandOn: true,
                isGood: [true, true, true, true],
                hsi: [1, 1, 1, 1],
                blink: false,
                jawClench: false,
                accelerometer: 0.04,
                gyro: 4,
                optics: 12
            )
        ]

        let summary = detector.summarize(framesBySecond: frames)

        #expect(summary.microArousalCount == 0)
    }

    @Test func nonArtifactEventCanTriggerWithoutOpticsSession() {
        let detector = MuseArousalDetector()
        let frames: [Int64: MuseSecondFrame] = [
            1: frame(
                headbandOn: true,
                isGood: [true, true, true, true],
                hsi: [1, 1, 4, 4],
                blink: false,
                jawClench: false,
                accelerometer: 0.25,
                gyro: 20,
                optics: nil
            )
        ]

        let summary = detector.summarize(framesBySecond: frames)

        #expect(summary.microArousalCount == 1)
    }

    @Test func confidenceIsClampedToConfiguredMaximum() {
        let detector = MuseArousalDetector()
        let frames: [Int64: MuseSecondFrame] = [
            1: frame(
                headbandOn: true,
                isGood: [true, true, true, true],
                hsi: [1, 1, 1, 1],
                blink: false,
                jawClench: false,
                accelerometer: 0.1,
                gyro: 6,
                optics: nil
            )
        ]

        let summary = detector.summarize(framesBySecond: frames)

        #expect(summary.confidence == MuseArousalHeuristicConstants.maximumConfidence)
    }

    @Test func confidenceIsZeroForEmptySession() {
        let detector = MuseArousalDetector()

        let summary = detector.summarize(framesBySecond: [:])

        #expect(summary.confidence == 0)
        #expect(summary.validSeconds == 0)
        #expect(summary.microArousalCount == 0)
        #expect(summary.awakeLikelihood == 0)
        #expect(summary.fitGuidance == .insufficientSignal)
    }

    @Test func awakeLikelihoodIsHighForSustainedMotionAndArtifacts() {
        let detector = MuseArousalDetector()
        let frames: [Int64: MuseSecondFrame] = [
            1: frame(
                headbandOn: true,
                isGood: [true, true, false, false],
                hsi: [4, 4, 4, 4],
                blink: true,
                jawClench: false,
                accelerometer: 0.32,
                gyro: 24,
                optics: nil
            ),
            2: frame(
                headbandOn: true,
                isGood: [true, false, false, true],
                hsi: [4, 4, 4, 4],
                blink: false,
                jawClench: true,
                accelerometer: 0.34,
                gyro: 26,
                optics: nil
            ),
            3: frame(
                headbandOn: true,
                isGood: [false, false, true, true],
                hsi: [4, 4, 4, 4],
                blink: true,
                jawClench: false,
                accelerometer: 0.3,
                gyro: 22,
                optics: nil
            )
        ]

        let summary = detector.summarize(framesBySecond: frames)

        #expect(summary.awakeLikelihood > 0.8)
        #expect(summary.decisions.count == 3)
    }

    @Test func awakeLikelihoodIsLowForStableQuietSession() {
        let detector = MuseArousalDetector()
        let frames: [Int64: MuseSecondFrame] = [
            1: frame(
                headbandOn: true,
                isGood: [true, true, true, true],
                hsi: [1, 1, 1, 1],
                blink: false,
                jawClench: false,
                accelerometer: 0.02,
                gyro: 1,
                optics: nil
            ),
            2: frame(
                headbandOn: true,
                isGood: [true, true, true, true],
                hsi: [1, 1, 1, 1],
                blink: false,
                jawClench: false,
                accelerometer: 0.02,
                gyro: 1,
                optics: nil
            ),
            3: frame(
                headbandOn: true,
                isGood: [true, true, true, true],
                hsi: [1, 1, 1, 1],
                blink: false,
                jawClench: false,
                accelerometer: 0.02,
                gyro: 1,
                optics: nil
            )
        ]

        let summary = detector.summarize(framesBySecond: frames)

        #expect(summary.awakeLikelihood < 0.1)
        #expect(summary.fitGuidance == .good)
    }

    @Test func fitGuidanceBecomesAdjustHeadbandWhenCoverageDrops() {
        let detector = MuseArousalDetector()
        let frames: [Int64: MuseSecondFrame] = [
            1: frame(
                headbandOn: true,
                isGood: [true, true, true, true],
                hsi: [1, 1, 1, 1],
                blink: false,
                jawClench: false,
                accelerometer: 0.02,
                gyro: 1,
                optics: nil
            ),
            2: frame(
                headbandOn: true,
                isGood: [true, false, false, true],
                hsi: [4, 4, 4, 4],
                blink: false,
                jawClench: false,
                accelerometer: 0.02,
                gyro: 1,
                optics: nil
            ),
            3: frame(
                headbandOn: true,
                isGood: [true, false, false, true],
                hsi: [4, 4, 4, 4],
                blink: false,
                jawClench: false,
                accelerometer: 0.02,
                gyro: 1,
                optics: nil
            )
        ]

        let summary = detector.summarize(framesBySecond: frames)

        #expect(summary.fitGuidance == .adjustHeadband)
    }

    @Test func fitGuidanceBecomesInsufficientSignalWhenQualityInputsMissing() {
        let detector = MuseArousalDetector()
        let frames: [Int64: MuseSecondFrame] = [
            1: MuseSecondFrame(
                headbandOn: true,
                blinkDetected: false,
                jawClenchDetected: false,
                isGoodChannels: nil,
                hsiPrecisionChannels: nil,
                maxAccelerometerMagnitude: 0.05,
                maxGyroMagnitude: 2,
                opticsPeakToPeak: nil,
                eegChannels: nil
            ),
            2: MuseSecondFrame(
                headbandOn: true,
                blinkDetected: false,
                jawClenchDetected: false,
                isGoodChannels: nil,
                hsiPrecisionChannels: nil,
                maxAccelerometerMagnitude: 0.05,
                maxGyroMagnitude: 2,
                opticsPeakToPeak: nil,
                eegChannels: nil
            ),
            3: MuseSecondFrame(
                headbandOn: true,
                blinkDetected: false,
                jawClenchDetected: false,
                isGoodChannels: [true, true, true, true],
                hsiPrecisionChannels: [1, 1, 1, 1],
                maxAccelerometerMagnitude: 0.05,
                maxGyroMagnitude: 2,
                opticsPeakToPeak: nil,
                eegChannels: nil
            )
        ]
        let summary = detector.summarize(framesBySecond: frames)

        #expect(summary.fitGuidance == .insufficientSignal)
    }

    private func frame(
        headbandOn: Bool,
        isGood: [Bool],
        hsi: [Double],
        blink: Bool,
        jawClench: Bool,
        accelerometer: Double,
        gyro: Double,
        optics: Double?
    ) -> MuseSecondFrame {
        MuseSecondFrame(
            headbandOn: headbandOn,
            blinkDetected: blink,
            jawClenchDetected: jawClench,
            isGoodChannels: isGood,
            hsiPrecisionChannels: hsi,
            maxAccelerometerMagnitude: accelerometer,
            maxGyroMagnitude: gyro,
            opticsPeakToPeak: optics,
            eegChannels: nil
        )
    }
}
