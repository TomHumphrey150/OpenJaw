import Foundation

enum MuseConnectPreset: Equatable, Sendable {
    case preset1031
    case preset1021
}

enum MuseServiceCoreAction: Equatable, Sendable {
    case startListening
    case stopListening
    case connect(MuseConnectPreset)
}

enum MuseConnectOutcome: Equatable, Sendable {
    case connected
    case needsLicense
    case needsUpdate
    case disconnected
    case timeout
}

enum MuseConnectDecision: Equatable, Sendable {
    case success
    case retry([MuseServiceCoreAction])
    case fail(MuseSessionServiceError)
}

struct MuseSessionServiceCore: Sendable {
    private(set) var scanTimeout: TimeInterval
    private(set) var scanStartedAt: Date?
    private(set) var currentPreset: MuseConnectPreset
    private(set) var hasTriedFallbackPreset: Bool
    private(set) var isRecording: Bool

    init(scanTimeout: TimeInterval = 8) {
        self.scanTimeout = scanTimeout
        scanStartedAt = nil
        currentPreset = .preset1031
        hasTriedFallbackPreset = false
        isRecording = false
    }

    mutating func beginScan(at now: Date) -> [MuseServiceCoreAction] {
        scanStartedAt = now
        return [.startListening]
    }

    func isScanTimedOut(at now: Date) -> Bool {
        guard let scanStartedAt else {
            return false
        }

        return now.timeIntervalSince(scanStartedAt) >= scanTimeout
    }

    mutating func beginConnectFlow() -> [MuseServiceCoreAction] {
        [.stopListening, .connect(currentPreset)]
    }

    mutating func registerConnectOutcome(_ outcome: MuseConnectOutcome) -> MuseConnectDecision {
        switch outcome {
        case .connected:
            return .success
        case .needsLicense:
            return .fail(.needsLicense)
        case .needsUpdate:
            return .fail(.needsUpdate)
        case .disconnected, .timeout:
            if !hasTriedFallbackPreset && currentPreset == .preset1031 {
                hasTriedFallbackPreset = true
                currentPreset = .preset1021
                return .retry([.stopListening, .connect(.preset1021)])
            }

            return .fail(.notConnected)
        }
    }

    mutating func resetPresetAttempts() {
        currentPreset = .preset1031
        hasTriedFallbackPreset = false
    }

    mutating func startRecording() throws {
        guard !isRecording else {
            throw MuseSessionServiceError.alreadyRecording
        }

        isRecording = true
    }

    mutating func stopRecording() throws {
        guard isRecording else {
            throw MuseSessionServiceError.notRecording
        }

        isRecording = false
    }

    mutating func resetRecordingState() {
        isRecording = false
    }
}
