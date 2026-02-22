#if !targetEnvironment(simulator)
import Foundation
import Testing
@testable import Telocare

struct MuseSDKAdapterDeviceTests {
    @Test func adaptsIsGoodPacketFromSdkFactory() {
        let adapter = MuseSDKPacketAdapter()
        let packet = makePacket(type: .isGood, timestampUs: 1_000_000, values: [1, 1, 0, 1])

        let parsed = adapter.adapt(packet)

        if case .isGood(let timestampUs, let channels) = parsed {
            #expect(timestampUs == 1_000_000)
            #expect(channels == [true, true, false, true])
        } else {
            #expect(Bool(false))
        }
    }

    @Test func adaptsHsiPrecisionPacketFromSdkFactory() {
        let adapter = MuseSDKPacketAdapter()
        let packet = makePacket(type: .hsiPrecision, timestampUs: 2_000_000, values: [1, 2, 4, 1])

        let parsed = adapter.adapt(packet)

        if case .hsiPrecision(let timestampUs, let channels) = parsed {
            #expect(timestampUs == 2_000_000)
            #expect(channels == [1, 2, 4, 1])
        } else {
            #expect(Bool(false))
        }
    }

    @Test func adaptsAccelerometerAndGyroPacketsFromSdkFactory() {
        let adapter = MuseSDKPacketAdapter()

        let accelerometerPacket = makePacket(type: .accelerometer, timestampUs: 3_000_000, values: [0.1, 0.2, 0.3])
        if case .accelerometer(let timestampUs, let x, let y, let z) = adapter.adapt(accelerometerPacket) {
            #expect(timestampUs == 3_000_000)
            #expect(x == 0.1)
            #expect(y == 0.2)
            #expect(z == 0.3)
        } else {
            #expect(Bool(false))
        }

        let gyroPacket = makePacket(type: .gyro, timestampUs: 3_100_000, values: [8, 9, 10])
        if case .gyro(let timestampUs, let x, let y, let z) = adapter.adapt(gyroPacket) {
            #expect(timestampUs == 3_100_000)
            #expect(x == 8)
            #expect(y == 9)
            #expect(z == 10)
        } else {
            #expect(Bool(false))
        }
    }

    @Test func adaptsOpticsPacketFromSdkFactory() {
        let adapter = MuseSDKPacketAdapter()
        let packet = makePacket(type: .optics, timestampUs: 4_000_000, values: [10, 11, 12, 13])

        let parsed = adapter.adapt(packet)

        if case .optics(let timestampUs, let channels) = parsed {
            #expect(timestampUs == 4_000_000)
            #expect(channels == [10, 11, 12, 13])
        } else {
            #expect(Bool(false))
        }
    }

    @Test func unsupportedPacketTypeReturnsNilWithoutCrashing() {
        let adapter = MuseSDKPacketAdapter()
        let packet = makePacket(type: .battery, timestampUs: 5_000_000, values: [4000, 85, 33])

        #expect(adapter.adapt(packet) == nil)
    }

    private func makePacket(
        type: IXNMuseDataPacketType,
        timestampUs: Int64,
        values: [Double]
    ) -> IXNMuseDataPacket {
        let rawValues = values.map { NSNumber(value: $0) }
        let packet = IXNMuseDataPacket.makePacket(type, timestamp: timestampUs, values: rawValues)

        guard let packet else {
            Issue.record("IXNMuseDataPacket.makePacket returned nil for \(type)")
            return IXNMuseDataPacket.makeUninitializedPacket(0)!
        }

        return packet
    }
}
#endif
