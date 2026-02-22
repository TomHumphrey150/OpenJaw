import Foundation

enum MuseRawPacketType: Equatable, Sendable {
    case isGood
    case hsiPrecision
    case accelerometer
    case gyro
    case optics
    case eeg
    case unsupported
}

enum MuseEegChannel: Int, CaseIterable, Sendable {
    case eeg1
    case eeg2
    case eeg3
    case eeg4
}

enum MuseMotionAxis: Int, CaseIterable, Sendable {
    case x
    case y
    case z
}

struct MuseRawPacket: Equatable, Sendable {
    let type: MuseRawPacketType
    let timestampUs: Int64
    let values: [Double]
}

struct MuseRawArtifactPacket: Equatable, Sendable {
    let timestampUs: Int64
    let headbandOn: Bool
    let blink: Bool
    let jawClench: Bool
}

enum MusePacket: Equatable, Sendable {
    case isGood(timestampUs: Int64, channels: [Bool])
    case hsiPrecision(timestampUs: Int64, channels: [Double])
    case accelerometer(timestampUs: Int64, x: Double, y: Double, z: Double)
    case gyro(timestampUs: Int64, x: Double, y: Double, z: Double)
    case optics(timestampUs: Int64, channels: [Double])
    case eeg(timestampUs: Int64, channels: [Double])
    case artifact(timestampUs: Int64, headbandOn: Bool, blink: Bool, jawClench: Bool)

    var timestampUs: Int64 {
        switch self {
        case .isGood(let timestampUs, _):
            return timestampUs
        case .hsiPrecision(let timestampUs, _):
            return timestampUs
        case .accelerometer(let timestampUs, _, _, _):
            return timestampUs
        case .gyro(let timestampUs, _, _, _):
            return timestampUs
        case .optics(let timestampUs, _):
            return timestampUs
        case .eeg(let timestampUs, _):
            return timestampUs
        case .artifact(let timestampUs, _, _, _):
            return timestampUs
        }
    }
}

protocol MuseDataPacketReading {
    var packetType: MuseRawPacketType { get }
    var timestampUs: Int64 { get }
    var valuesCount: Int { get }

    func eegValue(_ channel: MuseEegChannel) -> Double
    func accelerometerValue(_ axis: MuseMotionAxis) -> Double
    func gyroValue(_ axis: MuseMotionAxis) -> Double
    func opticsValue(channelIndex: Int) -> Double
}

protocol MuseArtifactPacketReading {
    var timestampUs: Int64 { get }
    var headbandOn: Bool { get }
    var blink: Bool { get }
    var jawClench: Bool { get }
}
