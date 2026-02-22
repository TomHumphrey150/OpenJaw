#if !targetEnvironment(simulator)
import Foundation

struct MuseSDKPacketAdapter {
    private let coreAdapter = MusePacketAdapterCore()

    func adapt(_ packet: IXNMuseDataPacket?) -> MusePacket? {
        guard let packet else {
            return nil
        }

        return coreAdapter.adapt(MuseSDKDataPacketReader(packet: packet))
    }

    func adapt(_ packet: IXNMuseArtifactPacket) -> MusePacket? {
        coreAdapter.adapt(MuseSDKArtifactPacketReader(packet: packet))
    }
}

private struct MuseSDKDataPacketReader: MuseDataPacketReading {
    let packet: IXNMuseDataPacket

    var packetType: MuseRawPacketType {
        switch packet.packetType() {
        case .isGood:
            return .isGood
        case .hsiPrecision:
            return .hsiPrecision
        case .accelerometer:
            return .accelerometer
        case .gyro:
            return .gyro
        case .optics:
            return .optics
        case .eeg:
            return .eeg
        default:
            return .unsupported
        }
    }

    var timestampUs: Int64 {
        packet.timestamp()
    }

    var valuesCount: Int {
        max(0, Int(packet.valuesSize()))
    }

    func eegValue(_ channel: MuseEegChannel) -> Double {
        packet.getEegChannelValue(Self.eegChannel(for: channel))
    }

    func accelerometerValue(_ axis: MuseMotionAxis) -> Double {
        packet.getAccelerometerValue(Self.accelerometerAxis(for: axis))
    }

    func gyroValue(_ axis: MuseMotionAxis) -> Double {
        packet.getGyroValue(Self.gyroAxis(for: axis))
    }

    func opticsValue(channelIndex: Int) -> Double {
        packet.getOpticsChannelValue(Self.opticsChannel(for: channelIndex))
    }

    private static func eegChannel(for channel: MuseEegChannel) -> IXNEeg {
        switch channel {
        case .eeg1:
            return requiredEnumValue(rawValue: 0, type: IXNEeg.self)
        case .eeg2:
            return requiredEnumValue(rawValue: 1, type: IXNEeg.self)
        case .eeg3:
            return requiredEnumValue(rawValue: 2, type: IXNEeg.self)
        case .eeg4:
            return requiredEnumValue(rawValue: 3, type: IXNEeg.self)
        }
    }

    private static func accelerometerAxis(for axis: MuseMotionAxis) -> IXNAccelerometer {
        switch axis {
        case .x:
            return requiredEnumValue(rawValue: 0, type: IXNAccelerometer.self)
        case .y:
            return requiredEnumValue(rawValue: 1, type: IXNAccelerometer.self)
        case .z:
            return requiredEnumValue(rawValue: 2, type: IXNAccelerometer.self)
        }
    }

    private static func gyroAxis(for axis: MuseMotionAxis) -> IXNGyro {
        switch axis {
        case .x:
            return requiredEnumValue(rawValue: 0, type: IXNGyro.self)
        case .y:
            return requiredEnumValue(rawValue: 1, type: IXNGyro.self)
        case .z:
            return requiredEnumValue(rawValue: 2, type: IXNGyro.self)
        }
    }

    private static func opticsChannel(for index: Int) -> IXNOptics {
        let clampedIndex = min(max(index, 0), 15)
        return requiredEnumValue(rawValue: clampedIndex, type: IXNOptics.self)
    }

    private static func requiredEnumValue<T: RawRepresentable>(
        rawValue: Int,
        type: T.Type
    ) -> T where T.RawValue == Int {
        guard let value = T(rawValue: rawValue) else {
            preconditionFailure("Unsupported \(type) raw value: \(rawValue)")
        }

        return value
    }
}

private struct MuseSDKArtifactPacketReader: MuseArtifactPacketReading {
    let packet: IXNMuseArtifactPacket

    var timestampUs: Int64 {
        packet.timestamp
    }

    var headbandOn: Bool {
        packet.headbandOn
    }

    var blink: Bool {
        packet.blink
    }

    var jawClench: Bool {
        packet.jawClench
    }
}
#endif
