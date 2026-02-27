import Foundation

enum MuseDiagnosticsCapturePhase: String, Equatable, Sendable, Codable {
    case setup
    case recording

    var storageDirectoryName: String {
        switch self {
        case .setup:
            return "setup"
        case .recording:
            return "sessions"
        }
    }

    var archivePrefix: String {
        switch self {
        case .setup:
            return "muse-setup-diagnostics"
        case .recording:
            return "muse-diagnostics"
        }
    }

    var exportSummaryTitle: String {
        switch self {
        case .setup:
            return "Telocare Muse setup diagnostics export summary"
        case .recording:
            return "Telocare Muse diagnostics export summary"
        }
    }
}

struct MuseDiagnosticsStorage {
    static let retentionDays = 7

    private let fileManager: FileManager
    private let nowProvider: () -> Date

    init(
        fileManager: FileManager = .default,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.nowProvider = nowProvider
    }

    func createSessionDirectory(
        startedAt: Date,
        capturePhase: MuseDiagnosticsCapturePhase
    ) throws -> URL {
        try purgeExpiredSessions()

        let directory = try phaseDirectory(capturePhase)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: startedAt).replacingOccurrences(of: ":", with: "-")
        let sessionName = "session-\(timestamp)-\(UUID().uuidString.lowercased())"
        let sessionDirectory = directory.appendingPathComponent(sessionName, isDirectory: true)
        try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: false)
        return sessionDirectory
    }

    func logsDirectory() throws -> URL {
        try ensureDirectory(
            rootDirectory().appendingPathComponent("logs", isDirectory: true)
        )
    }

    func purgeExpiredSessions() throws {
        let cutoffDate = nowProvider().addingTimeInterval(-TimeInterval(Self.retentionDays * 24 * 60 * 60))
        let resourceKeys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey, .isDirectoryKey]

        for capturePhase in MuseDiagnosticsCapturePhase.allCases {
            let directory = try phaseDirectory(capturePhase)
            let sessionDirectories = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )

            for sessionDirectory in sessionDirectories {
                let values = try sessionDirectory.resourceValues(forKeys: resourceKeys)
                guard values.isDirectory == true else {
                    continue
                }

                let referenceDate = values.creationDate ?? values.contentModificationDate
                guard let referenceDate, referenceDate < cutoffDate else {
                    continue
                }

                try fileManager.removeItem(at: sessionDirectory)
            }
        }
    }

    private func phaseDirectory(_ capturePhase: MuseDiagnosticsCapturePhase) throws -> URL {
        try ensureDirectory(
            rootDirectory().appendingPathComponent(capturePhase.storageDirectoryName, isDirectory: true)
        )
    }

    private func rootDirectory() throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return try ensureDirectory(
            applicationSupport.appendingPathComponent("MuseDiagnostics", isDirectory: true)
        )
    }

    private func ensureDirectory(_ directory: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return directory
            }

            throw CocoaError(.fileWriteFileExists)
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

extension MuseDiagnosticsCapturePhase: CaseIterable {}
