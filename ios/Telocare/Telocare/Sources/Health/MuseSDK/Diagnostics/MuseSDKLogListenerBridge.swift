#if !targetEnvironment(simulator)
import Foundation

final class MuseSDKLogListenerBridge: NSObject, IXNLogListener {
    private let onLogMessage: @Sendable (String) -> Void

    init(onLogMessage: @escaping @Sendable (String) -> Void = { _ in }) {
        self.onLogMessage = onLogMessage
        super.init()
    }

    func receiveLog(_ log: IXNLogPacket) {
        let message = "SDK[\(log.tag)] \(log.message)"

        onLogMessage(message)

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
