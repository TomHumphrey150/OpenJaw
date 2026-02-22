#if !targetEnvironment(simulator)
import Foundation

actor MuseSDKSessionService: MuseSessionService {
    private let scanTimeoutSeconds: TimeInterval
    private let connectTimeoutSeconds: TimeInterval
    private let scanPollIntervalNanoseconds: UInt64
    private let connectPollIntervalNanoseconds: UInt64

    private var core: MuseSessionServiceCore
    private var accumulator: MuseSessionAccumulator
    private let detector: MuseArousalDetector
    private let packetAdapter: MuseSDKPacketAdapter

    private let manager: IXNMuseManagerIos
    private var connectedMuse: IXNMuse?
    private var recordingStartedAt: Date?

    private var listListener: MuseSDKMuseListListenerBridge?
    private var connectionListener: MuseSDKConnectionListenerBridge?
    private var dataListener: MuseSDKDataListenerBridge?
    private var errorListener: MuseSDKErrorListenerBridge?

    private var latestConnectionState: MuseConnectionStateCode

    init(
        scanTimeoutSeconds: TimeInterval = 8,
        connectTimeoutSeconds: TimeInterval = 12,
        manager: IXNMuseManagerIos = IXNMuseManagerIos.sharedManager()
    ) {
        self.scanTimeoutSeconds = scanTimeoutSeconds
        self.connectTimeoutSeconds = connectTimeoutSeconds
        scanPollIntervalNanoseconds = 200_000_000
        connectPollIntervalNanoseconds = 150_000_000

        core = MuseSessionServiceCore(scanTimeout: scanTimeoutSeconds)
        accumulator = MuseSessionAccumulator()
        detector = MuseArousalDetector()
        packetAdapter = MuseSDKPacketAdapter()

        self.manager = manager
        connectedMuse = nil
        recordingStartedAt = nil

        listListener = nil
        connectionListener = nil
        dataListener = nil
        errorListener = nil

        latestConnectionState = .unknown
        self.manager.removeFromList(after: 0)
    }

    func scanForHeadbands() async throws -> [MuseHeadband] {
        for action in core.beginScan(at: Date()) {
            apply(action)
        }
        ensureListListenerRegistered()

        while !core.isScanTimedOut(at: Date()) {
            let discovered = manager.getMuses().map {
                MuseHeadband(id: $0.getMacAddress(), name: $0.getName())
            }
            if !discovered.isEmpty {
                manager.stopListening()
                return discovered
            }

            try await Task.sleep(nanoseconds: scanPollIntervalNanoseconds)
        }

        manager.stopListening()
        throw MuseSessionServiceError.noHeadbandFound
    }

    func connect(to headband: MuseHeadband, licenseData: Data?) async throws {
        let muse = try resolveMuse(for: headband)

        core.resetPresetAttempts()

        while true {
            let actions = core.beginConnectFlow()
            guard let connectPreset = actions.compactMap(connectPreset(from:)).first else {
                throw MuseSessionServiceError.unavailable
            }

            for action in actions {
                switch action {
                case .startListening:
                    manager.startListening()
                case .stopListening:
                    manager.stopListening()
                case .connect:
                    break
                }
            }

            prepareMuseForConnect(muse)
            if let licenseData {
                muse.setLicense(licenseData)
            }
            muse.setPreset(sdkPreset(from: connectPreset))
            muse.runAsynchronously()

            let outcome = await waitForConnectOutcome(muse)
            switch core.registerConnectOutcome(outcome) {
            case .success:
                guard muse.getModel() == .ms03 else {
                    cleanupConnectedMuse(muse)
                    throw MuseSessionServiceError.unsupportedHeadbandModel
                }

                connectedMuse = muse
                return
            case .retry:
                cleanupAfterFailedConnectAttempt(muse)
                try await Task.sleep(nanoseconds: 700_000_000)
            case .fail(let error):
                cleanupConnectedMuse(muse)
                throw error
            }
        }
    }

    func disconnect() async {
        core.resetRecordingState()
        recordingStartedAt = nil
        accumulator.reset()

        guard let muse = connectedMuse else {
            return
        }

        cleanupConnectedMuse(muse)
        connectedMuse = nil
    }

    func startRecording(at startDate: Date) async throws {
        guard let connectedMuse else {
            throw MuseSessionServiceError.notConnected
        }

        let state = MuseSDKConnectionMapper.code(from: connectedMuse.getConnectionState())
        if let error = MuseSDKConnectionMapper.error(for: state) {
            throw error
        }
        guard state == .connected else {
            throw MuseSessionServiceError.notConnected
        }

        try core.startRecording()
        recordingStartedAt = startDate
        accumulator.reset()
    }

    func stopRecording(at endDate: Date) async throws -> MuseRecordingSummary {
        try core.stopRecording()

        guard let recordingStartedAt else {
            throw MuseSessionServiceError.notRecording
        }

        self.recordingStartedAt = nil

        return accumulator.buildSummary(
            startedAt: recordingStartedAt,
            endedAt: endDate,
            detector: detector
        )
    }

    private func apply(_ action: MuseServiceCoreAction) {
        switch action {
        case .startListening:
            manager.startListening()
        case .stopListening:
            manager.stopListening()
        case .connect:
            return
        }
    }

    private func connectPreset(from action: MuseServiceCoreAction) -> MuseConnectPreset? {
        guard case .connect(let preset) = action else {
            return nil
        }

        return preset
    }

    private func resolveMuse(for headband: MuseHeadband) throws -> IXNMuse {
        let muses = manager.getMuses()

        if let exact = muses.first(where: { $0.getMacAddress() == headband.id }) {
            return exact
        }

        if let byName = muses.first(where: { $0.getName() == headband.name }) {
            return byName
        }

        throw MuseSessionServiceError.noHeadbandFound
    }

    private func prepareMuseForConnect(_ muse: IXNMuse) {
        ensureListeners()
        latestConnectionState = .unknown

        muse.unregisterAllListeners()

        if let connectionListener {
            muse.register(connectionListener)
        }
        if let errorListener {
            muse.register(errorListener)
        }
        if let dataListener {
            muse.register(dataListener, type: .isGood)
            muse.register(dataListener, type: .hsiPrecision)
            muse.register(dataListener, type: .accelerometer)
            muse.register(dataListener, type: .gyro)
            muse.register(dataListener, type: .optics)
            muse.register(dataListener, type: .eeg)
            muse.register(dataListener, type: .artifacts)
        }

        muse.enableDataTransmission(true)
        muse.enableException(false)
    }

    private func cleanupAfterFailedConnectAttempt(_ muse: IXNMuse) {
        muse.unregisterAllListeners()
        muse.disconnect()
    }

    private func cleanupConnectedMuse(_ muse: IXNMuse) {
        muse.unregisterAllListeners()
        muse.disconnect()
    }

    private func waitForConnectOutcome(_ muse: IXNMuse) async -> MuseConnectOutcome {
        let deadline = Date().addingTimeInterval(connectTimeoutSeconds)
        var sawConnecting = false

        while Date() < deadline {
            let state = MuseSDKConnectionMapper.code(from: muse.getConnectionState())
            latestConnectionState = state

            switch state {
            case .connected:
                return .connected
            case .needsLicense:
                return .needsLicense
            case .needsUpdate:
                return .needsUpdate
            case .connecting:
                sawConnecting = true
            case .disconnected:
                if sawConnecting {
                    return .disconnected
                }
            case .unknown:
                break
            }

            try? await Task.sleep(nanoseconds: connectPollIntervalNanoseconds)
        }

        return .timeout
    }

    private func sdkPreset(from preset: MuseConnectPreset) -> IXNMusePreset {
        switch preset {
        case .preset1031:
            return .preset1031
        case .preset1021:
            return .preset1021
        }
    }

    private func ensureListListenerRegistered() {
        if listListener == nil {
            listListener = MuseSDKMuseListListenerBridge {
                Task { [weak self] in
                    await self?.handleMuseListChanged()
                }
            }
        }

        manager.setMuseListener(listListener)
    }

    private func ensureListeners() {
        if connectionListener == nil {
            connectionListener = MuseSDKConnectionListenerBridge { packet in
                let mapped = MuseSDKConnectionMapper.code(from: packet.currentConnectionState)
                Task { [weak self] in
                    await self?.handleConnectionState(mapped)
                }
            }
        }

        if dataListener == nil {
            let packetAdapter = packetAdapter
            dataListener = MuseSDKDataListenerBridge(
                onDataPacket: { packet in
                    guard let packet, let parsed = packetAdapter.adapt(packet) else {
                        return
                    }

                    Task { [weak self] in
                        await self?.handlePacket(parsed)
                    }
                },
                onArtifactPacket: { packet in
                    guard let parsed = packetAdapter.adapt(packet) else {
                        return
                    }

                    Task { [weak self] in
                        await self?.handlePacket(parsed)
                    }
                }
            )
        }

        if errorListener == nil {
            errorListener = MuseSDKErrorListenerBridge { _ in
            }
        }
    }

    private func handleMuseListChanged() {
    }

    private func handleConnectionState(_ state: MuseConnectionStateCode) {
        latestConnectionState = state
    }

    private func handlePacket(_ packet: MusePacket) {
        guard recordingStartedAt != nil else {
            return
        }

        accumulator.ingest(packet)
    }
}
#endif
