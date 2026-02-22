#if !targetEnvironment(simulator)
import Foundation

final class MuseDiagnosticsRecorder {
    private let lock = NSLock()
    private let storage: MuseDiagnosticsStorage
    private var activeSession: MuseDiagnosticsSession?

    init(storage: MuseDiagnosticsStorage = MuseDiagnosticsStorage()) {
        self.storage = storage
    }

    func beginSession(startedAt: Date) {
        lock.lock()
        defer { lock.unlock() }

        guard activeSession == nil else {
            return
        }

        do {
            let session = try MuseDiagnosticsSession(storage: storage, startedAt: startedAt)
            activeSession = session
            session.recordServiceEvent("recording_started")
        } catch {
            MuseDiagnosticsLogger.error("Failed to start diagnostics session: \(error.localizedDescription)")
            activeSession = nil
        }
    }

    func recordDataPacket(_ packet: IXNMuseDataPacket?) {
        lock.lock()
        defer { lock.unlock() }
        activeSession?.recordDataPacket(packet)
    }

    func recordArtifactPacket(_ packet: IXNMuseArtifactPacket) {
        lock.lock()
        defer { lock.unlock() }
        activeSession?.recordArtifactPacket(packet)
    }

    func recordDecision(_ decision: MuseSecondDecision) {
        lock.lock()
        defer { lock.unlock() }
        activeSession?.recordDecision(decision)
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
        activeSession?.recordServiceEvent(message)
    }

    func finishSession(endedAt: Date, detectionSummary: MuseDetectionSummary?) -> [URL] {
        lock.lock()
        defer { lock.unlock() }

        guard let activeSession else {
            return []
        }

        let fileURLs = activeSession.finish(endedAt: endedAt, detectionSummary: detectionSummary)
        self.activeSession = nil
        return fileURLs
    }
}

private final class MuseDiagnosticsSession {
    private let startedAt: Date
    private let sessionDirectoryURL: URL
    private let museFileURL: URL
    private let eventWriter: MuseDiagnosticsEventWriter
    private let museFileWriter: IXNMuseFileWriter?
    private var lastFlushAt: Date

    init(storage: MuseDiagnosticsStorage, startedAt: Date) throws {
        self.startedAt = startedAt
        sessionDirectoryURL = try storage.createSessionDirectory(startedAt: startedAt)
        museFileURL = sessionDirectoryURL.appendingPathComponent("session.muse")
        eventWriter = try MuseDiagnosticsEventWriter(sessionDirectoryURL: sessionDirectoryURL)
        museFileWriter = IXNMuseFileFactory.museFileWriter(withPathString: museFileURL.path)
        lastFlushAt = startedAt
    }

    func recordDataPacket(_ packet: IXNMuseDataPacket?) {
        museFileWriter?.addDataPacket(1, packet: packet)
        flushIfNeeded(now: Date())
    }

    func recordArtifactPacket(_ packet: IXNMuseArtifactPacket) {
        museFileWriter?.addArtifactPacket(1, packet: packet)
        flushIfNeeded(now: Date())
    }

    func recordDecision(_ decision: MuseSecondDecision) {
        eventWriter.appendDecision(decision)
    }

    func recordServiceEvent(_ message: String) {
        eventWriter.appendServiceEvent(message)
    }

    func finish(endedAt: Date, detectionSummary: MuseDetectionSummary?) -> [URL] {
        if let detectionSummary {
            eventWriter.appendSummary(detectionSummary)
        }

        _ = museFileWriter?.flush()
        _ = museFileWriter?.close()

        let logFileURLs = MuseDiagnosticsLogger.latestLogFileURLs(limit: 2)
        var filesToReference = [museFileURL, eventWriter.decisionsFileURL]
        filesToReference.append(contentsOf: logFileURLs)

        do {
            try eventWriter.writeManifest(
                startedAt: startedAt,
                endedAt: endedAt,
                summary: detectionSummary,
                files: filesToReference + [eventWriter.manifestFileURL]
            )
        } catch {
            MuseDiagnosticsLogger.warn("Failed to write diagnostics manifest: \(error.localizedDescription)")
        }

        eventWriter.close()

        var resultURLs: [URL] = []
        for fileURL in [museFileURL, eventWriter.decisionsFileURL, eventWriter.manifestFileURL] + logFileURLs {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                resultURLs.append(fileURL)
            }
        }

        return uniqueURLs(in: resultURLs)
    }

    private func flushIfNeeded(now: Date) {
        if now.timeIntervalSince(lastFlushAt) < 5 {
            return
        }

        _ = museFileWriter?.flush()
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
