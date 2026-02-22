import Foundation

struct MusePacketAdapterCore {
    private let parser = MusePacketParser()

    func adapt<Packet: MuseDataPacketReading>(_ packet: Packet) -> MusePacket? {
        let rawPacket: MuseRawPacket

        switch packet.packetType {
        case .isGood:
            rawPacket = MuseRawPacket(
                type: .isGood,
                timestampUs: packet.timestampUs,
                values: MuseEegChannel.allCases.map { packet.eegValue($0) }
            )
        case .hsiPrecision:
            rawPacket = MuseRawPacket(
                type: .hsiPrecision,
                timestampUs: packet.timestampUs,
                values: MuseEegChannel.allCases.map { packet.eegValue($0) }
            )
        case .accelerometer:
            rawPacket = MuseRawPacket(
                type: .accelerometer,
                timestampUs: packet.timestampUs,
                values: MuseMotionAxis.allCases.map { packet.accelerometerValue($0) }
            )
        case .gyro:
            rawPacket = MuseRawPacket(
                type: .gyro,
                timestampUs: packet.timestampUs,
                values: MuseMotionAxis.allCases.map { packet.gyroValue($0) }
            )
        case .optics:
            let cappedCount = max(0, min(packet.valuesCount, 16))
            let values = (0..<cappedCount).map { packet.opticsValue(channelIndex: $0) }
            rawPacket = MuseRawPacket(type: .optics, timestampUs: packet.timestampUs, values: values)
        case .eeg:
            rawPacket = MuseRawPacket(
                type: .eeg,
                timestampUs: packet.timestampUs,
                values: MuseEegChannel.allCases.map { packet.eegValue($0) }
            )
        case .unsupported:
            rawPacket = MuseRawPacket(type: .unsupported, timestampUs: packet.timestampUs, values: [])
        }

        return parser.parse(dataPacket: rawPacket)
    }

    func adapt<Packet: MuseArtifactPacketReading>(_ packet: Packet) -> MusePacket? {
        parser.parse(
            artifactPacket: MuseRawArtifactPacket(
                timestampUs: packet.timestampUs,
                headbandOn: packet.headbandOn,
                blink: packet.blink,
                jawClench: packet.jawClench
            )
        )
    }
}
