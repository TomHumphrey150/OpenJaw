#if !targetEnvironment(simulator)
import Foundation

actor MuseSDKSessionService: MuseSessionService {
    private static let fitCalibrationRetentionWindowSeconds: Int64 = 30

    private let scanTimeoutSeconds: TimeInterval
    private let connectTimeoutSeconds: TimeInterval
    private let scanPollIntervalNanoseconds: UInt64
    private let connectPollIntervalNanoseconds: UInt64

    private var core: MuseSessionServiceCore
    private var recordingAccumulator: MuseSessionAccumulator
    private var fitAccumulator: MuseSessionAccumulator
    private let detector: MuseArousalDetector
    private let packetAdapter: MuseSDKPacketAdapter
    private let diagnosticsRecorder: MuseDiagnosticsRecorder

    private let manager: IXNMuseManagerIos
    private var connectedMuse: IXNMuse?
    private var connectedAt: Date?
    private var recordingStartedAt: Date?

    private var listListener: MuseSDKMuseListListenerBridge?
    private var connectionListener: MuseSDKConnectionListenerBridge?
    private var dataListener: MuseSDKDataListenerBridge?
    private var errorListener: MuseSDKErrorListenerBridge?
    private var sdkLogListener: MuseSDKLogListenerBridge?

    private var latestConnectionState: MuseConnectionStateCode
    private var fitTelemetry: RecordingTelemetry
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
        recordingAccumulator = MuseSessionAccumulator()
        fitAccumulator = MuseSessionAccumulator(
            retentionWindowSeconds: Self.fitCalibrationRetentionWindowSeconds
        )
        detector = MuseArousalDetector()
        packetAdapter = MuseSDKPacketAdapter()
        diagnosticsRecorder = MuseDiagnosticsRecorder()

        self.manager = manager
        connectedMuse = nil
        connectedAt = nil
        recordingStartedAt = nil

        listListener = nil
        connectionListener = nil
        dataListener = nil
        errorListener = nil
        sdkLogListener = nil

        latestConnectionState = .unknown
        fitTelemetry = RecordingTelemetry()
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
        configureSdkLogListener()
        let connectStartedAt = Date()
        diagnosticsRecorder.beginSetupSession(startedAt: connectStartedAt)
        let muse: IXNMuse
        do {
            muse = try resolveMuse(for: headband)
        } catch {
            _ = diagnosticsRecorder.finishSetupSession(
                endedAt: Date(),
                reason: "connect_failed_resolve_headband",
                detectionSummary: nil
            )
            throw error
        }

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
                    _ = diagnosticsRecorder.finishSetupSession(
                        endedAt: Date(),
                        reason: "connect_failed_unsupported_model",
                        detectionSummary: nil
                    )
                    MuseDiagnosticsLogger.warn("Muse connect failed due to unsupported model")
                    throw MuseSessionServiceError.unsupportedHeadbandModel
                }

                connectedMuse = muse
                connectedAt = Date()
                fitAccumulator.reset()
                fitTelemetry.reset()
                diagnosticsRecorder.ensureSetupSession(startedAt: connectedAt ?? connectStartedAt)
                MuseDiagnosticsLogger.info("Muse connected")
                return
            case .retry:
                MuseDiagnosticsLogger.warn("Muse connect retrying with fallback preset")
                cleanupAfterFailedConnectAttempt(muse)
                try await Task.sleep(nanoseconds: 700_000_000)
            case .fail(let error):
                cleanupConnectedMuse(muse)
                let setupSummary = fitAccumulator.detectionSummary(detector: detector)
                _ = diagnosticsRecorder.finishSetupSession(
                    endedAt: Date(),
                    reason: "connect_failed_\(error.diagnosticsLabel)",
                    detectionSummary: setupSummary
                )
                MuseDiagnosticsLogger.warn("Muse connect failed: \(error)")
                throw error
            }
        }
    }

    func disconnect() async {
        if recordingStartedAt != nil {
            diagnosticsRecorder.recordServiceEvent("recording_cancelled_disconnect")
            _ = diagnosticsRecorder.finishRecordingSession(endedAt: Date(), detectionSummary: nil)
        }

        let setupSummary = fitAccumulator.detectionSummary(detector: detector)
        _ = diagnosticsRecorder.finishSetupSession(
            endedAt: Date(),
            reason: "disconnect",
            detectionSummary: setupSummary
        )

        core.resetRecordingState()
        connectedAt = nil
        recordingStartedAt = nil
        fitTelemetry.reset()
        recordingTelemetry.reset()
        fitAccumulator.reset()
        recordingAccumulator.reset()

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
        let setupSummary = fitAccumulator.detectionSummary(detector: detector)
        _ = diagnosticsRecorder.finishSetupSession(
            endedAt: startDate,
            reason: "recording_started",
            detectionSummary: setupSummary
        )
        recordingStartedAt = startDate
        recordingTelemetry.reset()
        recordingAccumulator.reset()
        diagnosticsRecorder.beginRecordingSession(startedAt: startDate)
        MuseDiagnosticsLogger.info("Muse recording started")
    }

    func stopRecording(at endDate: Date) async throws -> MuseRecordingSummary {
        try core.stopRecording()

        guard let recordingStartedAt else {
            throw MuseSessionServiceError.notRecording
        }

        self.recordingStartedAt = nil

        let summary = recordingAccumulator.buildSummary(
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
        let diagnosticsFileURLs = diagnosticsRecorder.finishRecordingSession(
            endedAt: endDate,
            detectionSummary: summary.detectionSummary
        )

        MuseDiagnosticsLogger.info("Muse recording stopped")
        recordingTelemetry.reset()
        fitAccumulator.reset()
        fitTelemetry.reset()
        connectedAt = endDate

        return summary.recordingSummary.withDiagnosticsFileURLs(diagnosticsFileURLs)
    }

    func fitDiagnostics(at now: Date) async -> MuseLiveDiagnostics? {
        guard connectedMuse != nil else {
            return nil
        }
        guard recordingStartedAt == nil else {
            return nil
        }

        diagnosticsRecorder.ensureSetupSession(startedAt: connectedAt ?? now)

        let elapsedSeconds: Int
        if let connectedAt {
            elapsedSeconds = max(0, Int(now.timeIntervalSince(connectedAt)))
        } else {
            elapsedSeconds = 0
        }
        let lastPacketAgeSeconds = fitTelemetry.lastPacketAt.map { max(0, now.timeIntervalSince($0)) }
        let detectionSummary = fitAccumulator.detectionSummary(
            detector: detector,
            includeDecisions: true
        )

        let diagnostics = fitDiagnosticsSnapshot(
            elapsedSeconds: elapsedSeconds,
            detectionSummary: detectionSummary,
            telemetry: fitTelemetry,
            lastPacketAgeSeconds: lastPacketAgeSeconds,
            now: now
        )
        diagnosticsRecorder.recordFitSnapshot(diagnostics, at: now)
        return diagnostics
    }

    func snapshotSetupDiagnostics(at now: Date) async -> [URL] {
        let liveDiagnostics = await fitDiagnostics(at: now)
        return diagnosticsRecorder.snapshotSetupSession(at: now, latestDiagnostics: liveDiagnostics)
    }

    func latestSetupDiagnosticsFileURLs() async -> [URL] {
        diagnosticsRecorder.latestSetupSessionFileURLs()
    }

    func recordingDiagnostics(at now: Date) async -> MuseLiveDiagnostics? {
        guard let recordingStartedAt else {
            return nil
        }

        let detectionSummary = recordingAccumulator.detectionSummary(detector: detector)
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
            lastPacketAgeSeconds: lastPacketAgeSeconds,
            droppedPacketTypes: recordingTelemetry.droppedPacketTypes,
            setupDiagnosis: .unknown,
            windowPassRates: .zero,
            artifactRates: .zero,
            sdkWarningCounts: []
        )
    }

    private func fitDiagnosticsSnapshot(
        elapsedSeconds: Int,
        detectionSummary: MuseDetectionSummary,
        telemetry: RecordingTelemetry,
        lastPacketAgeSeconds: Double?,
        now: Date
    ) -> MuseLiveDiagnostics {
        let latestDecision = detectionSummary.decisions.last
        let sensorStatuses = MuseFitReadinessEvaluator.sensorStatuses(
            isGoodChannels: latestDecision?.isGoodChannels,
            hsiPrecisionChannels: latestDecision?.hsiPrecisionChannels
        )
        let goodChannelCount = MuseFitReadinessEvaluator.goodChannelCount(
            from: latestDecision?.isGoodChannels
        )
        let hsiGoodChannelCount = MuseFitReadinessEvaluator.hsiGoodChannelCount(
            from: latestDecision?.hsiPrecisionChannels
        )
        let isReceivingData = lastPacketAgeSeconds.map { $0 <= 3 } ?? false
        let fitReadiness = MuseFitReadinessEvaluator.evaluate(
            isReceivingData: isReceivingData,
            latestHeadbandOn: latestDecision?.headbandOn,
            latestHasQualityInputs: latestDecision?.hasQualityInputs,
            goodChannelCount: goodChannelCount,
            hsiGoodChannelCount: hsiGoodChannelCount,
            headbandOnCoverage: detectionSummary.headbandOnCoverage,
            qualityGateCoverage: detectionSummary.qualityGateCoverage
        )

        let window = buildSetupWindowSnapshot(
            decisions: detectionSummary.decisions,
            elapsedSeconds: elapsedSeconds,
            telemetry: telemetry,
            now: now
        )
        let setupDiagnosis = MuseSetupDiagnosticsClassifier.classify(
            MuseSetupClassifierInput(
                passRates: window.passRates,
                artifactRates: window.artifactRates,
                hasRecentDisconnectOrTimeoutEvent: window.hasRecentDisconnectOrTimeoutEvent,
                transportWarningCount: window.transportWarningCount
            )
        )

        return MuseLiveDiagnostics(
            elapsedSeconds: elapsedSeconds,
            signalConfidence: detectionSummary.confidence,
            awakeLikelihood: detectionSummary.awakeLikelihood,
            headbandOnCoverage: detectionSummary.headbandOnCoverage,
            qualityGateCoverage: detectionSummary.qualityGateCoverage,
            fitGuidance: detectionSummary.fitGuidance,
            rawDataPacketCount: telemetry.rawDataPacketCount,
            rawArtifactPacketCount: telemetry.rawArtifactPacketCount,
            parsedPacketCount: telemetry.parsedPacketCount,
            droppedPacketCount: telemetry.droppedPacketCount,
            droppedDataPacketTypeCounts: telemetry.droppedDataPacketTypeCounts,
            lastPacketAgeSeconds: lastPacketAgeSeconds,
            fitReadiness: fitReadiness,
            sensorStatuses: sensorStatuses,
            droppedPacketTypes: telemetry.droppedPacketTypes,
            setupDiagnosis: setupDiagnosis,
            windowPassRates: window.passRates,
            artifactRates: window.artifactRates,
            sdkWarningCounts: MuseDroppedPacketTypeCatalog.counts(from: window.sdkWarningCounts),
            latestHeadbandOn: latestDecision?.headbandOn,
            latestHasQualityInputs: latestDecision?.hasQualityInputs
        )
    }

    private func buildSetupWindowSnapshot(
        decisions: [MuseSecondDecision],
        elapsedSeconds: Int,
        telemetry: RecordingTelemetry,
        now: Date
    ) -> SetupWindowSnapshot {
        let windowTargetSeconds = min(
            MuseSetupDiagnosticsClassifier.windowSeconds,
            max(1, elapsedSeconds + 1)
        )
        let recentDecisions = Array(decisions.suffix(windowTargetSeconds))
        let sampleCount = recentDecisions.count

        let receivingPacketsRate = min(
            1,
            Double(sampleCount) / Double(windowTargetSeconds)
        )

        let headbandCoverageRate = rate(
            passCount: recentDecisions.filter(\.headbandOn).count,
            sampleCount: sampleCount
        )
        let hsiGood3Rate = rate(
            passCount: recentDecisions.filter {
                MuseFitReadinessEvaluator.hsiGoodChannelCount(from: $0.hsiPrecisionChannels) >=
                    MuseArousalHeuristicConstants.minimumGoodChannels
            }.count,
            sampleCount: sampleCount
        )
        let eegGood3Rate = rate(
            passCount: recentDecisions.filter {
                MuseFitReadinessEvaluator.goodChannelCount(from: $0.isGoodChannels) >=
                    MuseArousalHeuristicConstants.minimumGoodChannels
            }.count,
            sampleCount: sampleCount
        )
        let qualityGateRate = rate(
            passCount: recentDecisions.filter(\.qualityGateSatisfied).count,
            sampleCount: sampleCount
        )

        let blinkRate = rate(
            passCount: recentDecisions.filter(\.blinkDetected).count,
            sampleCount: sampleCount
        )
        let jawRate = rate(
            passCount: recentDecisions.filter(\.jawClenchDetected).count,
            sampleCount: sampleCount
        )

        let cutoff = now.addingTimeInterval(
            -Double(MuseSetupDiagnosticsClassifier.windowSeconds)
        )
        let sdkWarningCounts = telemetry.sdkWarningCounts(since: cutoff)
        let transportWarningCount = transportWarningCount(from: sdkWarningCounts)
        let hasRecentDisconnectOrTimeoutEvent = telemetry.hasDisconnectOrTimeoutEvent(since: cutoff)

        return SetupWindowSnapshot(
            passRates: MuseSetupPassRates(
                receivingPackets: receivingPacketsRate,
                headbandCoverage: headbandCoverageRate,
                hsiGood3: hsiGood3Rate,
                eegGood3: eegGood3Rate,
                qualityGate: qualityGateRate
            ),
            artifactRates: MuseSetupArtifactRates(
                blinkTrueRate: blinkRate,
                jawClenchTrueRate: jawRate
            ),
            sdkWarningCounts: sdkWarningCounts,
            transportWarningCount: transportWarningCount,
            hasRecentDisconnectOrTimeoutEvent: hasRecentDisconnectOrTimeoutEvent
        )
    }

    private func rate(passCount: Int, sampleCount: Int) -> Double {
        guard sampleCount > 0 else {
            return 0
        }

        return Double(passCount) / Double(sampleCount)
    }

    private func transportWarningCount(from sdkWarningCounts: [Int: Int]) -> Int {
        sdkWarningCounts.reduce(into: 0) { total, entry in
            if MuseDroppedPacketTypeCatalog.label(for: entry.key) == "optics" {
                return
            }

            total += entry.value
        }
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
                Task { [weak self] in
                    await self?.handleServiceEventMessage(message)
                }
            }
        }
    }

    private func handleMuseListChanged() {
    }

    private func handleConnectionState(_ state: MuseConnectionStateCode) {
        latestConnectionState = state
        diagnosticsRecorder.recordConnectionState(state)
        let now = Date()
        fitTelemetry.recordConnectionState(state, now: now)
        recordingTelemetry.recordConnectionState(state, now: now)
    }

    private func handleDataPacket(
        parsedPacket: MusePacket?,
        packetTypeCode: Int?
    ) {
        guard connectedMuse != nil else {
            return
        }

        let now = Date()
        let isRecording = recordingStartedAt != nil
        if isRecording {
            recordingTelemetry.recordDataPacket(
                now: now,
                packetTypeCode: packetTypeCode,
                parsed: parsedPacket != nil
            )
        } else {
            fitTelemetry.recordDataPacket(
                now: now,
                packetTypeCode: packetTypeCode,
                parsed: parsedPacket != nil
            )
        }

        guard let parsedPacket else {
            return
        }

        if isRecording {
            recordingAccumulator.ingest(parsedPacket)
            return
        }

        fitAccumulator.ingest(parsedPacket)
    }

    private func handleArtifactPacket(parsedPacket: MusePacket?) {
        guard connectedMuse != nil else {
            return
        }

        let now = Date()
        let isRecording = recordingStartedAt != nil
        if isRecording {
            recordingTelemetry.recordArtifactPacket(now: now, parsed: parsedPacket != nil)
        } else {
            fitTelemetry.recordArtifactPacket(now: now, parsed: parsedPacket != nil)
        }

        guard let parsedPacket else {
            return
        }

        if isRecording {
            recordingAccumulator.ingest(parsedPacket)
            return
        }

        fitAccumulator.ingest(parsedPacket)
    }

    private func handleSdkLogMessage(_ message: String) {
        guard connectedMuse != nil else {
            return
        }
        guard let packetTypeCode = MuseSdkWarningParser.negativeTimestampPacketTypeCode(in: message) else {
            return
        }

        let now = Date()
        fitTelemetry.recordSdkWarning(packetTypeCode: packetTypeCode, now: now)
        recordingTelemetry.recordSdkWarning(packetTypeCode: packetTypeCode, now: now)
    }

    private func handleServiceEventMessage(_ message: String) {
        guard connectedMuse != nil else {
            return
        }
        guard MuseSdkWarningParser.isDisconnectOrTimeoutServiceEvent(message) else {
            return
        }

        let now = Date()
        fitTelemetry.recordDisconnectOrTimeoutEvent(now: now)
        recordingTelemetry.recordDisconnectOrTimeoutEvent(now: now)
    }

    private func configureSdkLogListener() {
        guard let logManager = IXNLogManager.instance() else {
            sdkLogListener = nil
            return
        }

        let listener = MuseSDKLogListenerBridge { [weak self] message in
            Task { [weak self] in
                await self?.handleSdkLogMessage(message)
            }
        }
        logManager.setLogListener(listener)
        logManager.setMinimumSeverity(.sevVerbose)
        sdkLogListener = listener
    }
}

private struct SetupWindowSnapshot: Sendable {
    let passRates: MuseSetupPassRates
    let artifactRates: MuseSetupArtifactRates
    let sdkWarningCounts: [Int: Int]
    let transportWarningCount: Int
    let hasRecentDisconnectOrTimeoutEvent: Bool
}

private struct RecordingTelemetry: Sendable {
    private static let retentionSeconds: TimeInterval = 120

    var rawDataPacketCount: Int
    var rawArtifactPacketCount: Int
    var parsedPacketCount: Int
    var droppedPacketCount: Int
    var droppedDataPacketTypeCounts: [Int: Int]
    var lastPacketAt: Date?
    var sdkWarningEvents: [TimedPacketTypeEvent]
    var disconnectOrTimeoutEvents: [Date]

    init() {
        rawDataPacketCount = 0
        rawArtifactPacketCount = 0
        parsedPacketCount = 0
        droppedPacketCount = 0
        droppedDataPacketTypeCounts = [:]
        lastPacketAt = nil
        sdkWarningEvents = []
        disconnectOrTimeoutEvents = []
    }

    mutating func reset() {
        rawDataPacketCount = 0
        rawArtifactPacketCount = 0
        parsedPacketCount = 0
        droppedPacketCount = 0
        droppedDataPacketTypeCounts = [:]
        lastPacketAt = nil
        sdkWarningEvents = []
        disconnectOrTimeoutEvents = []
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

    mutating func recordSdkWarning(packetTypeCode: Int, now: Date) {
        sdkWarningEvents.append(TimedPacketTypeEvent(packetTypeCode: packetTypeCode, at: now))
        pruneEvents(now: now)
    }

    mutating func recordDisconnectOrTimeoutEvent(now: Date) {
        disconnectOrTimeoutEvents.append(now)
        pruneEvents(now: now)
    }

    mutating func recordConnectionState(_ state: MuseConnectionStateCode, now: Date) {
        if state == .disconnected {
            recordDisconnectOrTimeoutEvent(now: now)
        } else {
            pruneEvents(now: now)
        }
    }

    func sdkWarningCounts(since cutoff: Date) -> [Int: Int] {
        sdkWarningEvents.reduce(into: [:]) { result, event in
            guard event.recordedAt >= cutoff else {
                return
            }
            result[event.packetTypeCode, default: 0] += 1
        }
    }

    func hasDisconnectOrTimeoutEvent(since cutoff: Date) -> Bool {
        disconnectOrTimeoutEvents.contains { $0 >= cutoff }
    }

    var droppedTypeSummary: String {
        if droppedPacketTypes.isEmpty {
            return "none"
        }

        return droppedPacketTypes
            .map { "\($0.code):\($0.count)" }
            .joined(separator: ",")
    }

    var droppedPacketTypes: [MuseDroppedPacketTypeCount] {
        MuseDroppedPacketTypeCatalog.counts(from: droppedDataPacketTypeCounts)
    }

    private mutating func pruneEvents(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retentionSeconds)
        sdkWarningEvents.removeAll { $0.recordedAt < cutoff }
        disconnectOrTimeoutEvents.removeAll { $0 < cutoff }
    }
}

private struct TimedPacketTypeEvent: Sendable {
    let packetTypeCode: Int
    let recordedAt: Date

    init(packetTypeCode: Int, at recordedAt: Date) {
        self.packetTypeCode = packetTypeCode
        self.recordedAt = recordedAt
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

private extension MuseSessionServiceError {
    var diagnosticsLabel: String {
        switch self {
        case .unavailable:
            return "unavailable"
        case .noHeadbandFound:
            return "no_headband_found"
        case .notConnected:
            return "not_connected"
        case .needsLicense:
            return "needs_license"
        case .needsUpdate:
            return "needs_update"
        case .unsupportedHeadbandModel:
            return "unsupported_headband_model"
        case .alreadyRecording:
            return "already_recording"
        case .notRecording:
            return "not_recording"
        }
    }
}
#endif
