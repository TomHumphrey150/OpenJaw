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
    private let diagnosticsRecorder: MuseDiagnosticsRecorder

    private let manager: IXNMuseManagerIos
    private var connectedMuse: IXNMuse?
    private var recordingStartedAt: Date?

    private var listListener: MuseSDKMuseListListenerBridge?
    private var connectionListener: MuseSDKConnectionListenerBridge?
    private var dataListener: MuseSDKDataListenerBridge?
    private var errorListener: MuseSDKErrorListenerBridge?
    private var sdkLogListener: MuseSDKLogListenerBridge?

    private var latestConnectionState: MuseConnectionStateCode
    private var recordingTelemetry: RecordingTelemetry

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
        diagnosticsRecorder = MuseDiagnosticsRecorder()

        self.manager = manager
        connectedMuse = nil
        recordingStartedAt = nil

        listListener = nil
        connectionListener = nil
        dataListener = nil
        errorListener = nil
        sdkLogListener = Self.makeSdkLogListener()

        latestConnectionState = .unknown
        recordingTelemetry = RecordingTelemetry()
        self.manager.removeFromList(after: 0)
    }

    func scanForHeadbands() async throws -> [MuseHeadband] {
        MuseDiagnosticsLogger.info("Muse scan started")
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
                MuseDiagnosticsLogger.info("Muse scan discovered \(discovered.count) device(s)")
                return discovered
            }

            try await Task.sleep(nanoseconds: scanPollIntervalNanoseconds)
        }

        manager.stopListening()
        MuseDiagnosticsLogger.warn("Muse scan timed out")
        throw MuseSessionServiceError.noHeadbandFound
    }

    func connect(to headband: MuseHeadband, licenseData: Data?) async throws {
        MuseDiagnosticsLogger.info("Muse connect requested for \(headband.name)")
        let muse = try resolveMuse(for: headband)

        core.resetPresetAttempts()

        while true {
            let actions = core.beginConnectFlow()
            guard let connectPreset = actions.compactMap(connectPreset(from:)).first else {
                throw MuseSessionServiceError.unavailable
            }

            diagnosticsRecorder.recordConnectPreset(connectPreset)
            MuseDiagnosticsLogger.info("Muse connect attempt using \(connectPreset.diagnosticsLabel)")

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
            diagnosticsRecorder.recordServiceEvent("connect_outcome=\(outcome.diagnosticsLabel)")

            switch core.registerConnectOutcome(outcome) {
            case .success:
                guard muse.getModel() == .ms03 else {
                    cleanupConnectedMuse(muse)
                    MuseDiagnosticsLogger.warn("Muse connect failed due to unsupported model")
                    throw MuseSessionServiceError.unsupportedHeadbandModel
                }

                connectedMuse = muse
                MuseDiagnosticsLogger.info("Muse connected")
                return
            case .retry:
                MuseDiagnosticsLogger.warn("Muse connect retrying with fallback preset")
                cleanupAfterFailedConnectAttempt(muse)
                try await Task.sleep(nanoseconds: 700_000_000)
            case .fail(let error):
                cleanupConnectedMuse(muse)
                MuseDiagnosticsLogger.warn("Muse connect failed: \(error)")
                throw error
            }
        }
    }

    func disconnect() async {
        if recordingStartedAt != nil {
            diagnosticsRecorder.recordServiceEvent("recording_cancelled_disconnect")
            _ = diagnosticsRecorder.finishSession(endedAt: Date(), detectionSummary: nil)
        }

        core.resetRecordingState()
        recordingStartedAt = nil
        recordingTelemetry.reset()
        accumulator.reset()

        guard let muse = connectedMuse else {
            return
        }

        cleanupConnectedMuse(muse)
        connectedMuse = nil
        MuseDiagnosticsLogger.info("Muse disconnected")
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
        recordingTelemetry.reset()
        accumulator.reset()
        diagnosticsRecorder.beginSession(startedAt: startDate)
        MuseDiagnosticsLogger.info("Muse recording started")
    }

    func stopRecording(at endDate: Date) async throws -> MuseRecordingSummary {
        try core.stopRecording()

        guard let recordingStartedAt else {
            throw MuseSessionServiceError.notRecording
        }

        self.recordingStartedAt = nil

        let summary = accumulator.buildSummary(
            startedAt: recordingStartedAt,
            endedAt: endDate,
            detector: detector,
            onDecision: { [diagnosticsRecorder] decision in
                diagnosticsRecorder.recordDecision(decision)
            }
        )

        diagnosticsRecorder.recordServiceEvent("recording_stopped")
        diagnosticsRecorder.recordServiceEvent(
            "ingest_counts raw_data=\(recordingTelemetry.rawDataPacketCount) raw_artifact=\(recordingTelemetry.rawArtifactPacketCount) parsed=\(recordingTelemetry.parsedPacketCount) dropped=\(recordingTelemetry.droppedPacketCount) dropped_types=\(recordingTelemetry.droppedTypeSummary)"
        )
        let diagnosticsFileURLs = diagnosticsRecorder.finishSession(
            endedAt: endDate,
            detectionSummary: summary.detectionSummary
        )

        MuseDiagnosticsLogger.info("Muse recording stopped")
        recordingTelemetry.reset()

        return summary.recordingSummary.withDiagnosticsFileURLs(diagnosticsFileURLs)
    }

    func recordingDiagnostics(at now: Date) async -> MuseLiveDiagnostics? {
        guard let recordingStartedAt else {
            return nil
        }

        let detectionSummary = accumulator.detectionSummary(detector: detector)
        let elapsedSeconds = max(0, Int(now.timeIntervalSince(recordingStartedAt)))
        let lastPacketAgeSeconds = recordingTelemetry.lastPacketAt.map { max(0, now.timeIntervalSince($0)) }

        return MuseLiveDiagnostics(
            elapsedSeconds: elapsedSeconds,
            signalConfidence: detectionSummary.confidence,
            awakeLikelihood: detectionSummary.awakeLikelihood,
            headbandOnCoverage: detectionSummary.headbandOnCoverage,
            qualityGateCoverage: detectionSummary.qualityGateCoverage,
            fitGuidance: detectionSummary.fitGuidance,
            rawDataPacketCount: recordingTelemetry.rawDataPacketCount,
            rawArtifactPacketCount: recordingTelemetry.rawArtifactPacketCount,
            parsedPacketCount: recordingTelemetry.parsedPacketCount,
            droppedPacketCount: recordingTelemetry.droppedPacketCount,
            droppedDataPacketTypeCounts: recordingTelemetry.droppedDataPacketTypeCounts,
            lastPacketAgeSeconds: lastPacketAgeSeconds
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
            let diagnosticsRecorder = diagnosticsRecorder
            dataListener = MuseSDKDataListenerBridge(
                onDataPacket: { packet in
                    diagnosticsRecorder.recordDataPacket(packet)
                    let packetTypeCode = packet.map { Int($0.packetType().rawValue) }
                    let parsed = packet.flatMap(packetAdapter.adapt)
                    Task { [weak self] in
                        await self?.handleDataPacket(
                            parsedPacket: parsed,
                            packetTypeCode: packetTypeCode
                        )
                    }
                },
                onArtifactPacket: { packet in
                    diagnosticsRecorder.recordArtifactPacket(packet)
                    let parsed = packetAdapter.adapt(packet)
                    Task { [weak self] in
                        await self?.handleArtifactPacket(parsedPacket: parsed)
                    }
                }
            )
        }

        if errorListener == nil {
            let diagnosticsRecorder = diagnosticsRecorder
            errorListener = MuseSDKErrorListenerBridge { error in
                let message = "Muse SDK error code=\(error.code) info=\(error.info)"
                diagnosticsRecorder.recordServiceEvent(message)
                MuseDiagnosticsLogger.warn(message)
            }
        }
    }

    private func handleMuseListChanged() {
    }

    private func handleConnectionState(_ state: MuseConnectionStateCode) {
        latestConnectionState = state
        diagnosticsRecorder.recordConnectionState(state)
    }

    private func handleDataPacket(
        parsedPacket: MusePacket?,
        packetTypeCode: Int?
    ) {
        guard recordingStartedAt != nil else {
            return
        }

        recordingTelemetry.recordDataPacket(
            now: Date(),
            packetTypeCode: packetTypeCode,
            parsed: parsedPacket != nil
        )

        guard let parsedPacket else {
            return
        }

        accumulator.ingest(parsedPacket)
    }

    private func handleArtifactPacket(parsedPacket: MusePacket?) {
        guard recordingStartedAt != nil else {
            return
        }

        recordingTelemetry.recordArtifactPacket(now: Date(), parsed: parsedPacket != nil)

        guard let parsedPacket else {
            return
        }

        accumulator.ingest(parsedPacket)
    }

    nonisolated private static func makeSdkLogListener() -> MuseSDKLogListenerBridge? {
        let listener = MuseSDKLogListenerBridge()
        if let logManager = IXNLogManager.instance() {
            logManager.setLogListener(listener)
            logManager.setMinimumSeverity(.sevVerbose)
            return listener
        }

        return nil
    }
}

private struct RecordingTelemetry: Sendable {
    var rawDataPacketCount: Int
    var rawArtifactPacketCount: Int
    var parsedPacketCount: Int
    var droppedPacketCount: Int
    var droppedDataPacketTypeCounts: [Int: Int]
    var lastPacketAt: Date?

    init() {
        rawDataPacketCount = 0
        rawArtifactPacketCount = 0
        parsedPacketCount = 0
        droppedPacketCount = 0
        droppedDataPacketTypeCounts = [:]
        lastPacketAt = nil
    }

    mutating func reset() {
        rawDataPacketCount = 0
        rawArtifactPacketCount = 0
        parsedPacketCount = 0
        droppedPacketCount = 0
        droppedDataPacketTypeCounts = [:]
        lastPacketAt = nil
    }

    mutating func recordDataPacket(
        now: Date,
        packetTypeCode: Int?,
        parsed: Bool
    ) {
        rawDataPacketCount += 1
        lastPacketAt = now
        if parsed {
            parsedPacketCount += 1
            return
        }

        droppedPacketCount += 1
        if let packetTypeCode {
            droppedDataPacketTypeCounts[packetTypeCode, default: 0] += 1
        }
    }

    mutating func recordArtifactPacket(now: Date, parsed: Bool) {
        rawArtifactPacketCount += 1
        lastPacketAt = now
        if parsed {
            parsedPacketCount += 1
            return
        }

        droppedPacketCount += 1
    }

    var droppedTypeSummary: String {
        if droppedDataPacketTypeCounts.isEmpty {
            return "none"
        }

        return droppedDataPacketTypeCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
    }
}

private extension MuseConnectPreset {
    var diagnosticsLabel: String {
        switch self {
        case .preset1031:
            return "preset1031"
        case .preset1021:
            return "preset1021"
        }
    }
}

private extension MuseConnectOutcome {
    var diagnosticsLabel: String {
        switch self {
        case .connected:
            return "connected"
        case .needsLicense:
            return "needs_license"
        case .needsUpdate:
            return "needs_update"
        case .disconnected:
            return "disconnected"
        case .timeout:
            return "timeout"
        }
    }
}
#endif
