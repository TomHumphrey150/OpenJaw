import Foundation
import ZIPFoundation

enum MuseDiagnosticsExportBundleError: Error {
    case noFiles
    case failedToCreateBundle
    case failedToCopyFiles
    case failedToCreateArchive
}

struct MuseDiagnosticsExportBundle {
    static func make(
        fileURLs: [URL],
        capturePhase: MuseDiagnosticsCapturePhase = .recording,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let existingFileURLs = fileURLs.filter {
            fileManager.fileExists(atPath: $0.path)
        }
        guard !existingFileURLs.isEmpty else {
            throw MuseDiagnosticsExportBundleError.noFiles
        }

        let exportsDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MuseDiagnosticsExports", isDirectory: true)

        if !fileManager.fileExists(atPath: exportsDirectory.path) {
            try fileManager.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
        }

        try purgeExpiredBundles(in: exportsDirectory, now: now, fileManager: fileManager)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
        let bundleName = "\(capturePhase.archivePrefix)-\(timestamp)-\(UUID().uuidString.lowercased())"
        let bundleDirectory = exportsDirectory
            .appendingPathComponent(bundleName, isDirectory: true)
        let archiveURL = exportsDirectory
            .appendingPathComponent(bundleName)
            .appendingPathExtension("zip")

        do {
            try fileManager.createDirectory(at: bundleDirectory, withIntermediateDirectories: false)
        } catch {
            throw MuseDiagnosticsExportBundleError.failedToCreateBundle
        }
        defer {
            try? fileManager.removeItem(at: bundleDirectory)
        }

        let discoveredFileDescriptions = try existingFileURLs.map { sourceURL in
            let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            return "- \(sourceURL.lastPathComponent) (\(size) bytes)"
        }

        let copiedFileURLs = try copyFiles(
            existingFileURLs,
            into: bundleDirectory,
            fileManager: fileManager
        )

        let exportedFileDescriptions = try copiedFileURLs.map { copiedURL in
            let attributes = try fileManager.attributesOfItem(atPath: copiedURL.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            return "- \(copiedURL.lastPathComponent) (\(size) bytes)"
        }

        let summaryPrefix: String
        let summaryPurpose: String
        switch capturePhase {
        case .setup:
            summaryPrefix = "muse-setup-diagnostics-export-summary"
            summaryPurpose = "Purpose: Share setup-stage diagnostics for fit and transport debugging."
        case .recording:
            summaryPrefix = "muse-diagnostics-export-summary"
            summaryPurpose = "Purpose: Share summary plus core decision files."
        }

        let exportFileURL = bundleDirectory
            .appendingPathComponent("\(summaryPrefix)-\(timestamp)")
            .appendingPathExtension("txt")

        let summary = """
        \(capturePhase.exportSummaryTitle)
        Created: \(ISO8601DateFormatter().string(from: now))
        \(summaryPurpose)

        Source files discovered:
        \(discoveredFileDescriptions.joined(separator: "\n"))

        Files prepared for sharing:
        \(exportedFileDescriptions.joined(separator: "\n"))
        """

        do {
            try summary.write(to: exportFileURL, atomically: true, encoding: .utf8)
        } catch {
            throw MuseDiagnosticsExportBundleError.failedToCreateBundle
        }

        do {
            try fileManager.zipItem(
                at: bundleDirectory,
                to: archiveURL,
                shouldKeepParent: false,
                compressionMethod: .deflate
            )
        } catch {
            try? fileManager.removeItem(at: archiveURL)
            throw MuseDiagnosticsExportBundleError.failedToCreateArchive
        }

        return archiveURL
    }

    private static func purgeExpiredBundles(
        in exportsDirectory: URL,
        now: Date,
        fileManager: FileManager
    ) throws {
        let cutoffDate = now.addingTimeInterval(-(24 * 60 * 60))
        let resourceKeys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey, .isDirectoryKey]
        let entries = try fileManager.contentsOfDirectory(
            at: exportsDirectory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        for entry in entries {
            let values = try entry.resourceValues(forKeys: resourceKeys)
            let referenceDate = values.creationDate ?? values.contentModificationDate
            guard let referenceDate else {
                continue
            }
            guard referenceDate < cutoffDate else {
                continue
            }

            try fileManager.removeItem(at: entry)
        }
    }

    private static func copyFiles(
        _ fileURLs: [URL],
        into bundleDirectory: URL,
        fileManager: FileManager
    ) throws -> [URL] {
        var copiedURLs: [URL] = []

        for sourceURL in fileURLs {
            let destinationURL = uniqueDestinationURL(
                in: bundleDirectory,
                for: sourceURL.lastPathComponent,
                fileManager: fileManager
            )

            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                copiedURLs.append(destinationURL)
            } catch {
                throw MuseDiagnosticsExportBundleError.failedToCopyFiles
            }
        }

        return copiedURLs
    }

    private static func uniqueDestinationURL(
        in directory: URL,
        for fileName: String,
        fileManager: FileManager
    ) -> URL {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension
        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        var index = 0

        while true {
            let candidateName: String
            if index == 0 {
                candidateName = fileName
            } else if fileExtension.isEmpty {
                candidateName = "\(baseName)-\(index)"
            } else {
                candidateName = "\(baseName)-\(index).\(fileExtension)"
            }

            let candidateURL = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }

            index += 1
        }
    }
}
