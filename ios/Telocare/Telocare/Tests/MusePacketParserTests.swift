import Foundation
import Testing
@testable import Telocare

struct MusePacketParserTests {
    @Test func parsesIsGoodPacketIntoBooleanChannels() {
        let parser = MusePacketParser()
        let packet = MuseRawPacket(
            type: .isGood,
            timestampUs: 1_000_000,
            values: [1, 1, 0, 1]
        )

        let parsed = parser.parse(dataPacket: packet)

        if case .isGood(_, let channels) = parsed {
            #expect(channels == [true, true, false, true])
        } else {
            #expect(Bool(false))
        }
    }

    @Test func parsesHsiPrecisionPacket() {
        let parser = MusePacketParser()
        let packet = MuseRawPacket(
            type: .hsiPrecision,
            timestampUs: 2_000_000,
            values: [1, 2, 4, 1]
        )

        let parsed = parser.parse(dataPacket: packet)

        if case .hsiPrecision(_, let channels) = parsed {
            #expect(channels == [1, 2, 4, 1])
        } else {
            #expect(Bool(false))
        }
    }

    @Test func parsesAccelerometerPacket() {
        let parser = MusePacketParser()
        let packet = MuseRawPacket(
            type: .accelerometer,
            timestampUs: 3_000_000,
            values: [0.1, 0.2, 0.3]
        )

        let parsed = parser.parse(dataPacket: packet)

        if case .accelerometer(_, let x, let y, let z) = parsed {
            #expect(x == 0.1)
            #expect(y == 0.2)
            #expect(z == 0.3)
        } else {
            #expect(Bool(false))
        }
    }

    @Test func parsesOpticsPacketWithVariableChannelCount() {
        let parser = MusePacketParser()
        let packet = MuseRawPacket(
            type: .optics,
            timestampUs: 4_000_000,
            values: [8, 9, 10, 11, 12, 13, 14, 15]
        )

        let parsed = parser.parse(dataPacket: packet)

        if case .optics(_, let channels) = parsed {
            #expect(channels.count == 8)
            #expect(channels[0] == 8)
            #expect(channels[7] == 15)
        } else {
            #expect(Bool(false))
        }
    }

    @Test func rejectsUnsupportedAndNonFinitePackets() {
        let parser = MusePacketParser()

        let unsupported = MuseRawPacket(type: .unsupported, timestampUs: 5_000_000, values: [])
        #expect(parser.parse(dataPacket: unsupported) == nil)

        let nonFinite = MuseRawPacket(
            type: .gyro,
            timestampUs: 5_100_000,
            values: [1, .infinity, 3]
        )
        #expect(parser.parse(dataPacket: nonFinite) == nil)
    }

    @Test func parsesArtifactPacket() {
        let parser = MusePacketParser()
        let packet = MuseRawArtifactPacket(
            timestampUs: 6_000_000,
            headbandOn: true,
            blink: false,
            jawClench: true
        )

        let parsed = parser.parse(artifactPacket: packet)

        if case .artifact(_, let headbandOn, let blink, let jawClench) = parsed {
            #expect(headbandOn == true)
            #expect(blink == false)
            #expect(jawClench == true)
        } else {
            #expect(Bool(false))
        }
    }

    @Test func adapterCoreUsesOnlyGetterFamilyForAccelerometerType() {
        let adapter = MusePacketAdapterCore()
        let spy = DataPacketSpy(type: .accelerometer, timestampUs: 7_000_000, valuesCount: 3)

        _ = adapter.adapt(spy)

        #expect(spy.eegCalls == 0)
        #expect(spy.accelerometerCalls == 3)
        #expect(spy.gyroCalls == 0)
        #expect(spy.opticsCalls == 0)
    }

    @Test func adapterCoreUsesOnlyGetterFamilyForOpticsType() {
        let adapter = MusePacketAdapterCore()
        let spy = DataPacketSpy(type: .optics, timestampUs: 8_000_000, valuesCount: 4)

        _ = adapter.adapt(spy)

        #expect(spy.eegCalls == 0)
        #expect(spy.accelerometerCalls == 0)
        #expect(spy.gyroCalls == 0)
        #expect(spy.opticsCalls == 4)
    }
}

private final class DataPacketSpy: MuseDataPacketReading {
    let packetType: MuseRawPacketType
    let timestampUs: Int64
    let valuesCount: Int

    private(set) var eegCalls = 0
    private(set) var accelerometerCalls = 0
    private(set) var gyroCalls = 0
    private(set) var opticsCalls = 0

    init(type: MuseRawPacketType, timestampUs: Int64, valuesCount: Int) {
        packetType = type
        self.timestampUs = timestampUs
        self.valuesCount = valuesCount
    }

    func eegValue(_ channel: MuseEegChannel) -> Double {
        _ = channel
        eegCalls += 1
        return 1
    }

    func accelerometerValue(_ axis: MuseMotionAxis) -> Double {
        _ = axis
        accelerometerCalls += 1
        return 0.25
    }

    func gyroValue(_ axis: MuseMotionAxis) -> Double {
        _ = axis
        gyroCalls += 1
        return 12
    }

    func opticsValue(channelIndex: Int) -> Double {
        _ = channelIndex
        opticsCalls += 1
        return 10
    }
}
