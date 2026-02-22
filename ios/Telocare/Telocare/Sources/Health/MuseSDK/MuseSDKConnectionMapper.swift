import Foundation

enum MuseConnectionStateCode: Equatable, Sendable {
    case unknown
    case connecting
    case connected
    case disconnected
    case needsUpdate
    case needsLicense
}

enum MuseSDKConnectionMapper {
    static func error(for state: MuseConnectionStateCode) -> MuseSessionServiceError? {
        switch state {
        case .needsLicense:
            return .needsLicense
        case .needsUpdate:
            return .needsUpdate
        default:
            return nil
        }
    }
}

#if !targetEnvironment(simulator)
extension MuseSDKConnectionMapper {
    static func code(from state: IXNConnectionState) -> MuseConnectionStateCode {
        switch state {
        case .unknown:
            return .unknown
        case .connecting:
            return .connecting
        case .connected:
            return .connected
        case .disconnected:
            return .disconnected
        case .needsUpdate:
            return .needsUpdate
        case .needsLicense:
            return .needsLicense
        @unknown default:
            return .unknown
        }
    }
}
#endif
