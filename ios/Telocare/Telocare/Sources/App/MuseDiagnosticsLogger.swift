import CocoaLumberjackSwift
import Foundation

enum MuseDiagnosticsLogger {
    private static let lock = NSLock()
    private static var configured = false
    private static var fileLogger: DDFileLogger?

    static func bootstrap(storage: MuseDiagnosticsStorage = MuseDiagnosticsStorage()) {
        lock.lock()
        defer { lock.unlock() }

        guard !configured else {
            return
        }

        let logFileManager: DDLogFileManagerDefault
        do {
            let logsDirectory = try storage.logsDirectory()
            logFileManager = DDLogFileManagerDefault(logsDirectory: logsDirectory.path)
        } catch {
            logFileManager = DDLogFileManagerDefault()
        }

        let logger = DDFileLogger(logFileManager: logFileManager)
        logger.rollingFrequency = 24 * 60 * 60
        logger.logFileManager.maximumNumberOfLogFiles = UInt(MuseDiagnosticsStorage.retentionDays)

        DDLog.add(logger, with: .verbose)
        DDLog.add(DDOSLogger.sharedInstance, with: .info)

        fileLogger = logger
        configured = true
        DDLogInfo("Muse diagnostics logger configured")
    }

    static func debug(_ message: String) {
        DDLogDebug("\(message)")
    }

    static func info(_ message: String) {
        DDLogInfo("\(message)")
    }

    static func warn(_ message: String) {
        DDLogWarn("\(message)")
    }

    static func error(_ message: String) {
        DDLogError("\(message)")
    }

    static func latestLogFileURLs(limit: Int = 1) -> [URL] {
        lock.lock()
        defer { lock.unlock() }

        guard let fileLogger else {
            return []
        }

        let sortedFiles = fileLogger.logFileManager.sortedLogFileInfos
        let selectedFiles = sortedFiles.prefix(max(0, limit))
        return selectedFiles.map { URL(fileURLWithPath: $0.filePath) }
    }
}
