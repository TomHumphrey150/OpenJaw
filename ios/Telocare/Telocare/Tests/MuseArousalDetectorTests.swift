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
