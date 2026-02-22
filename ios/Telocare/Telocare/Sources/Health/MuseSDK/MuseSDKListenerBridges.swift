#if !targetEnvironment(simulator)
import Foundation

final class MuseSDKMuseListListenerBridge: NSObject, IXNMuseListener {
    private let onMuseListChanged: () -> Void

    init(onMuseListChanged: @escaping () -> Void) {
        self.onMuseListChanged = onMuseListChanged
    }

    func museListChanged() {
        onMuseListChanged()
    }
}

final class MuseSDKConnectionListenerBridge: NSObject, IXNMuseConnectionListener {
    private let onConnectionPacket: (IXNMuseConnectionPacket) -> Void

    init(onConnectionPacket: @escaping (IXNMuseConnectionPacket) -> Void) {
        self.onConnectionPacket = onConnectionPacket
    }

    func receive(_ packet: IXNMuseConnectionPacket, muse: IXNMuse?) {
        _ = muse
        onConnectionPacket(packet)
    }
}

final class MuseSDKDataListenerBridge: NSObject, IXNMuseDataListener {
    private let onDataPacket: (IXNMuseDataPacket?) -> Void
    private let onArtifactPacket: (IXNMuseArtifactPacket) -> Void

    init(
        onDataPacket: @escaping (IXNMuseDataPacket?) -> Void,
        onArtifactPacket: @escaping (IXNMuseArtifactPacket) -> Void
    ) {
        self.onDataPacket = onDataPacket
        self.onArtifactPacket = onArtifactPacket
    }

    func receive(_ packet: IXNMuseDataPacket?, muse: IXNMuse?) {
        _ = muse
        onDataPacket(packet)
    }

    func receive(_ packet: IXNMuseArtifactPacket, muse: IXNMuse?) {
        _ = muse
        onArtifactPacket(packet)
    }
}

final class MuseSDKErrorListenerBridge: NSObject, IXNMuseErrorListener {
    private let onError: (IXNError) -> Void

    init(onError: @escaping (IXNError) -> Void) {
        self.onError = onError
    }

    func receiveError(_ error: IXNError, muse: IXNMuse?) {
        _ = muse
        onError(error)
    }
}
#endif
