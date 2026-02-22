import Foundation

enum MuseConnectionState: Equatable, Sendable {
    case disconnected
    case scanning
    case discovered(MuseHeadband)
    case connecting(MuseHeadband)
    case connected(MuseHeadband)
    case needsLicense
    case needsUpdate
    case failed(String)

    var headband: MuseHeadband? {
        switch self {
        case .discovered(let headband), .connecting(let headband), .connected(let headband):
            return headband
        case .disconnected, .scanning, .needsLicense, .needsUpdate, .failed:
            return nil
        }
    }
}

enum MuseRecordingState: Equatable, Sendable {
    case idle
    case recording(startedAt: Date)
    case stopped(MuseRecordingSummary)
}
