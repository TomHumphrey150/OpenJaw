import Foundation

struct MusePacketParser {
    func parse(dataPacket rawPacket: MuseRawPacket) -> MusePacket? {
        guard rawPacket.timestampUs > 0 else {
            return nil
        }

        switch rawPacket.type {
        case .isGood:
            guard let channels = validatedFixedChannels(rawPacket.values, count: 4) else {
                return nil
            }

            return .isGood(timestampUs: rawPacket.timestampUs, channels: channels.map { $0 >= 0.5 })
        case .hsiPrecision:
            guard let channels = validatedFixedChannels(rawPacket.values, count: 4) else {
                return nil
            }

            return .hsiPrecision(timestampUs: rawPacket.timestampUs, channels: channels)
        case .accelerometer:
            guard let axes = validatedAxes(rawPacket.values) else {
                return nil
            }

            return .accelerometer(
                timestampUs: rawPacket.timestampUs,
                x: axes[0],
                y: axes[1],
                z: axes[2]
            )
        case .gyro:
            guard let axes = validatedAxes(rawPacket.values) else {
                return nil
            }

            return .gyro(
                timestampUs: rawPacket.timestampUs,
                x: axes[0],
                y: axes[1],
                z: axes[2]
            )
        case .optics:
            guard let channels = validatedVariableChannels(rawPacket.values, minimumCount: 1) else {
                return nil
            }

            return .optics(timestampUs: rawPacket.timestampUs, channels: channels)
        case .eeg:
            guard let channels = validatedFixedChannels(rawPacket.values, count: 4) else {
                return nil
            }

            return .eeg(timestampUs: rawPacket.timestampUs, channels: channels)
        case .unsupported:
            return nil
        }
    }

    func parse(artifactPacket rawPacket: MuseRawArtifactPacket) -> MusePacket? {
        guard rawPacket.timestampUs > 0 else {
            return nil
        }

        return .artifact(
            timestampUs: rawPacket.timestampUs,
            headbandOn: rawPacket.headbandOn,
            blink: rawPacket.blink,
            jawClench: rawPacket.jawClench
        )
    }

    private func validatedFixedChannels(_ values: [Double], count: Int) -> [Double]? {
        guard values.count >= count else {
            return nil
        }

        let channels = Array(values.prefix(count))
        guard channels.allSatisfy(\.isFinite) else {
            return nil
        }

        return channels
    }

    private func validatedVariableChannels(_ values: [Double], minimumCount: Int) -> [Double]? {
        guard values.count >= minimumCount else {
            return nil
        }
        guard values.allSatisfy(\.isFinite) else {
            return nil
        }

        return values
    }

    private func validatedAxes(_ values: [Double]) -> [Double]? {
        guard values.count >= 3 else {
            return nil
        }

        let axes = Array(values.prefix(3))
        guard axes.allSatisfy(\.isFinite) else {
            return nil
        }

        return axes
    }
}
