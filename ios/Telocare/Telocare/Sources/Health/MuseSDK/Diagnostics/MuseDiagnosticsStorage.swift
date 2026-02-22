import Foundation

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

    func createSessionDirectory(startedAt: Date) throws -> URL {
        try purgeExpiredSessions()

        let directory = try sessionsDirectory()
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
        let directory = try sessionsDirectory()
        let resourceKeys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey, .isDirectoryKey]
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

    private func sessionsDirectory() throws -> URL {
        try ensureDirectory(
            rootDirectory().appendingPathComponent("sessions", isDirectory: true)
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
