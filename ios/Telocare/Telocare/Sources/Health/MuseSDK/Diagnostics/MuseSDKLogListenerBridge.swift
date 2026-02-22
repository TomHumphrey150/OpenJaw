#if !targetEnvironment(simulator)
import Foundation

final class MuseSDKLogListenerBridge: NSObject, IXNLogListener {
    func receiveLog(_ log: IXNLogPacket) {
        let message = "SDK[\(log.tag)] \(log.message)"

        switch log.severity {
        case .sevVerbose, .sevDebug:
            MuseDiagnosticsLogger.debug(message)
        case .sevInfo:
            MuseDiagnosticsLogger.info(message)
        case .sevWarn:
            MuseDiagnosticsLogger.warn(message)
        case .sevError, .sevFatal:
            MuseDiagnosticsLogger.error(message)
        case .total:
            MuseDiagnosticsLogger.debug(message)
        @unknown default:
            MuseDiagnosticsLogger.debug(message)
        }
    }
}
#endif
