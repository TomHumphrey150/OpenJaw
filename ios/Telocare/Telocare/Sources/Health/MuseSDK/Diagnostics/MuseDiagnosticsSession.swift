#if !targetEnvironment(simulator)
import Foundation

final class MuseDiagnosticsRecorder {
    private let lock = NSLock()
    private let storage: MuseDiagnosticsStorage
    private var activeSetupSession: MuseDiagnosticsSession?
    private var activeRecordingSession: MuseDiagnosticsSession?
    private var latestSetupDiagnosticsURLs: [URL]

    init(storage: MuseDiagnosticsStorage = MuseDiagnosticsStorage()) {
        self.storage = storage
        latestSetupDiagnosticsURLs = []
    }

    func beginSetupSession(startedAt: Date) {
        lock.lock()
        defer { lock.unlock() }

        guard activeSetupSession == nil else {
            return
        }

        do {
            let session = try MuseDiagnosticsSession(
                storage: storage,
                startedAt: startedAt,
                capturePhase: .setup
            )
            activeSetupSession = session
            session.recordServiceEvent("setup_started")
        } catch {
            activeSetupSession = nil
            MuseDiagnosticsLogger.error("Failed to start setup diagnostics session: \(error.localizedDescription)")
        }
    }

    func ensureSetupSession(startedAt: Date) {
        lock.lock()
        defer { lock.unlock() }
        ensureSetupSessionIfNeeded(startedAt: startedAt)
    }

    func beginRecordingSession(startedAt: Date) {
        lock.lock()
        defer { lock.unlock() }

        guard activeRecordingSession == nil else {
            return
        }

        do {
            let session = try MuseDiagnosticsSession(
                storage: storage,
                startedAt: startedAt,
                capturePhase: .recording
            )
            activeRecordingSession = session
            session.recordServiceEvent("recording_started")
        } catch {
            activeRecordingSession = nil
            MuseDiagnosticsLogger.error("Failed to start recording diagnostics session: \(error.localizedDescription)")
        }
    }

    func finishSetupSession(
        endedAt: Date,
        reason: String,
        detectionSummary: MuseDetectionSummary?
    ) -> [URL] {
        lock.lock()
        defer { lock.unlock() }

        guard let activeSetupSession else {
            return latestSetupDiagnosticsURLs
        }

        activeSetupSession.recordServiceEvent("setup_finished reason=\(reason)")
        let fileURLs = activeSetupSession.finish(endedAt: endedAt, detectionSummary: detectionSummary)
        self.activeSetupSession = nil
        latestSetupDiagnosticsURLs = fileURLs
        return fileURLs
    }

    func snapshotSetupSession(at now: Date, latestDiagnostics: MuseLiveDiagnostics?) -> [URL] {
        lock.lock()
        defer { lock.unlock() }

        if activeSetupSession == nil {
            return latestSetupDiagnosticsURLs
        }

        if let latestDiagnostics {
            activeSetupSession?.recordFitSnapshot(latestDiagnostics, at: now)
        }

        guard let activeSetupSession else {
            return latestSetupDiagnosticsURLs
        }

        activeSetupSession.recordServiceEvent("setup_snapshot_export_requested")
        let fileURLs = activeSetupSession.finish(endedAt: now, detectionSummary: nil)
        self.activeSetupSession = nil
        latestSetupDiagnosticsURLs = fileURLs
        return fileURLs
    }

    func latestSetupSessionFileURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return latestSetupDiagnosticsURLs
    }

    func recordDataPacket(_ packet: IXNMuseDataPacket?) {
        lock.lock()
        defer { lock.unlock() }
        activeSetupSession?.recordDataPacket(packet)
        activeRecordingSession?.recordDataPacket(packet)
    }

    func recordArtifactPacket(_ packet: IXNMuseArtifactPacket) {
        lock.lock()
        defer { lock.unlock() }
        activeSetupSession?.recordArtifactPacket(packet)
        activeRecordingSession?.recordArtifactPacket(packet)
    }

    func recordDecision(_ decision: MuseSecondDecision) {
        lock.lock()
        defer { lock.unlock() }
        activeRecordingSession?.recordDecision(decision)
    }

    func recordFitSnapshot(_ diagnostics: MuseLiveDiagnostics, at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        activeSetupSession?.recordFitSnapshot(diagnostics, at: date)
    }

    func recordConnectionState(_ state: MuseConnectionStateCode) {
        recordServiceEvent("connection_state=\(state.diagnosticsLabel)")
    }

    func recordConnectPreset(_ preset: MuseConnectPreset) {
        recordServiceEvent("connect_preset=\(preset.diagnosticsLabel)")
    }

    func recordServiceEvent(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        activeSetupSession?.recordServiceEvent(message)
        activeRecordingSession?.recordServiceEvent(message)
    }

    func finishRecordingSession(
        endedAt: Date,
        detectionSummary: MuseDetectionSummary?
    ) -> [URL] {
        lock.lock()
        defer { lock.unlock() }

        guard let activeRecordingSession else {
            return []
        }

        let fileURLs = activeRecordingSession.finish(endedAt: endedAt, detectionSummary: detectionSummary)
        self.activeRecordingSession = nil
        return fileURLs
    }

    private func ensureSetupSessionIfNeeded(startedAt: Date) {
        if activeSetupSession != nil {
            return
        }

        do {
            let session = try MuseDiagnosticsSession(
                storage: storage,
                startedAt: startedAt,
                capturePhase: .setup
            )
            session.recordServiceEvent("setup_started")
            activeSetupSession = session
        } catch {
            activeSetupSession = nil
            MuseDiagnosticsLogger.error("Failed to ensure setup diagnostics session: \(error.localizedDescription)")
        }
    }
}

private final class MuseDiagnosticsSession {
    private static let setupSegmentDurationSeconds: TimeInterval = 60
    private static let setupSegmentLimit = 5
    private static let fileWriterID: Int32 = 1

    private let startedAt: Date
    private let capturePhase: MuseDiagnosticsCapturePhase
    private let sessionDirectoryURL: URL
    private let eventWriter: MuseDiagnosticsEventWriter
    private var recordingMuseFileURL: URL?
    private var recordingMuseFileWriter: IXNMuseFileWriter?
    private var setupSegments: [SetupRawSegment]
    private var lastFlushAt: Date

    init(
        storage: MuseDiagnosticsStorage,
        startedAt: Date,
        capturePhase: MuseDiagnosticsCapturePhase
    ) throws {
        self.startedAt = startedAt
        self.capturePhase = capturePhase
        sessionDirectoryURL = try storage.createSessionDirectory(
            startedAt: startedAt,
            capturePhase: capturePhase
        )
        eventWriter = try MuseDiagnosticsEventWriter(
            sessionDirectoryURL: sessionDirectoryURL,
            capturePhase: capturePhase
        )
        setupSegments = []
        lastFlushAt = startedAt

        if capturePhase == .recording {
            let museFileURL = sessionDirectoryURL.appendingPathComponent("session.muse")
            recordingMuseFileURL = museFileURL
            recordingMuseFileWriter = IXNMuseFileFactory.museFileWriter(withPathString: museFileURL.path)
        } else {
            recordingMuseFileURL = nil
            recordingMuseFileWriter = nil
        }
    }

    func recordDataPacket(_ packet: IXNMuseDataPacket?) {
        let now = Date()

        if capturePhase == .recording {
            recordingMuseFileWriter?.addDataPacket(Self.fileWriterID, packet: packet)
            flushIfNeeded(now: now)
            return
        }

        ensureSetupSegment(now: now)
        setupSegments.last?.writer?.addDataPacket(Self.fileWriterID, packet: packet)
        flushIfNeeded(now: now)
    }

    func recordArtifactPacket(_ packet: IXNMuseArtifactPacket) {
        let now = Date()

        if capturePhase == .recording {
            recordingMuseFileWriter?.addArtifactPacket(Self.fileWriterID, packet: packet)
            flushIfNeeded(now: now)
            return
        }

        ensureSetupSegment(now: now)
        setupSegments.last?.writer?.addArtifactPacket(Self.fileWriterID, packet: packet)
        flushIfNeeded(now: now)
    }

    func recordDecision(_ decision: MuseSecondDecision) {
        eventWriter.appendDecision(decision)
    }

    func recordFitSnapshot(_ diagnostics: MuseLiveDiagnostics, at date: Date = Date()) {
        eventWriter.appendFitSnapshot(diagnostics, at: date)
    }

    func recordServiceEvent(_ message: String) {
        eventWriter.appendServiceEvent(message)
    }

    func finish(endedAt: Date, detectionSummary: MuseDetectionSummary?) -> [URL] {
        if let detectionSummary {
            eventWriter.appendSummary(detectionSummary)
        }

        closeRawWriters()

        let logFileURLs = MuseDiagnosticsLogger.latestLogFileURLs(limit: 2)
        let rawFileURLs = existingRawFileURLs()
        var filesToReference = rawFileURLs
        filesToReference.append(eventWriter.decisionsFileURL)
        filesToReference.append(contentsOf: logFileURLs)
        filesToReference.append(eventWriter.manifestFileURL)

        do {
            try eventWriter.writeManifest(
                startedAt: startedAt,
                endedAt: endedAt,
                summary: detectionSummary,
                files: filesToReference
            )
        } catch {
            MuseDiagnosticsLogger.warn("Failed to write diagnostics manifest: \(error.localizedDescription)")
        }

        eventWriter.close()

        var resultURLs = rawFileURLs
        resultURLs.append(eventWriter.decisionsFileURL)
        resultURLs.append(eventWriter.manifestFileURL)
        resultURLs.append(contentsOf: logFileURLs)
        return uniqueURLs(in: resultURLs.filter { FileManager.default.fileExists(atPath: $0.path) })
    }

    private func ensureSetupSegment(now: Date) {
        if setupSegments.isEmpty {
            openSetupSegment(startedAt: now)
            return
        }

        guard let lastStartedAt = setupSegments.last?.startedAt else {
            openSetupSegment(startedAt: now)
            return
        }

        if now.timeIntervalSince(lastStartedAt) < Self.setupSegmentDurationSeconds {
            return
        }

        closeCurrentSetupSegment()
        openSetupSegment(startedAt: now)
        trimSetupSegmentsIfNeeded()
    }

    private func openSetupSegment(startedAt: Date) {
        let index = setupSegments.last.map(\.index).map { $0 + 1 } ?? 1
        let segmentFileName = String(format: "setup-segment-%04d.muse", index)
        let segmentURL = sessionDirectoryURL.appendingPathComponent(segmentFileName)
        let writer = IXNMuseFileFactory.museFileWriter(withPathString: segmentURL.path)
        setupSegments.append(
            SetupRawSegment(
                index: index,
                startedAt: startedAt,
                url: segmentURL,
                writer: writer
            )
        )
    }

    private func closeCurrentSetupSegment() {
        guard !setupSegments.isEmpty else {
            return
        }

        _ = setupSegments[setupSegments.count - 1].writer?.flush()
        _ = setupSegments[setupSegments.count - 1].writer?.close()
        setupSegments[setupSegments.count - 1].writer = nil
    }

    private func trimSetupSegmentsIfNeeded() {
        while setupSegments.count > Self.setupSegmentLimit {
            var removed = setupSegments.removeFirst()
            _ = removed.writer?.flush()
            _ = removed.writer?.close()
            removed.writer = nil
            try? FileManager.default.removeItem(at: removed.url)
        }
    }

    private func closeRawWriters() {
        _ = recordingMuseFileWriter?.flush()
        _ = recordingMuseFileWriter?.close()
        recordingMuseFileWriter = nil

        for index in setupSegments.indices {
            _ = setupSegments[index].writer?.flush()
            _ = setupSegments[index].writer?.close()
            setupSegments[index].writer = nil
        }
    }

    private func existingRawFileURLs() -> [URL] {
        if capturePhase == .recording {
            guard let recordingMuseFileURL else {
                return []
            }
            return [recordingMuseFileURL]
        }

        return setupSegments.map(\.url).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func flushIfNeeded(now: Date) {
        if now.timeIntervalSince(lastFlushAt) < 5 {
            return
        }

        _ = recordingMuseFileWriter?.flush()
        _ = setupSegments.last?.writer?.flush()
        lastFlushAt = now
    }

    private func uniqueURLs(in urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var unique: [URL] = []

        for url in urls {
            if seen.insert(url.path).inserted {
                unique.append(url)
            }
        }

        return unique
    }
}

private struct SetupRawSegment {
    let index: Int
    let startedAt: Date
    let url: URL
    var writer: IXNMuseFileWriter?
}

private extension MuseConnectionStateCode {
    var diagnosticsLabel: String {
        switch self {
        case .unknown:
            return "unknown"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .disconnected:
            return "disconnected"
        case .needsLicense:
            return "needs_license"
        case .needsUpdate:
            return "needs_update"
        }
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
#endif
