import Foundation
import Testing
import ZIPFoundation
@testable import Telocare

struct MuseDiagnosticsExportBundleTests {
    @Test func makeCreatesFullDiagnosticsZipArchive() throws {
        let fileManager = FileManager.default
        let rootDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("muse-export-tests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: rootDirectory)
        }

        let sessionFileURL = rootDirectory.appendingPathComponent("session.muse")
        let decisionsFileURL = rootDirectory.appendingPathComponent("decisions.ndjson")
        let manifestFileURL = rootDirectory.appendingPathComponent("manifest.json")
        let logFileURL = rootDirectory.appendingPathComponent("diagnostics.log")

        try Data([0x01, 0x02, 0x03]).write(to: sessionFileURL)
        try Data("{\"type\":\"second\"}\n".utf8).write(to: decisionsFileURL)
        try Data("{\"schemaVersion\":1}".utf8).write(to: manifestFileURL)
        try Data("log".utf8).write(to: logFileURL)

        let exportArchiveURL = try MuseDiagnosticsExportBundle.make(
            fileURLs: [sessionFileURL, decisionsFileURL, manifestFileURL, logFileURL],
            now: Date(timeIntervalSince1970: 1_700_000_000),
            fileManager: fileManager
        )

        defer {
            try? fileManager.removeItem(at: exportArchiveURL)
        }

        #expect(exportArchiveURL.pathExtension == "zip")
        #expect(fileManager.fileExists(atPath: exportArchiveURL.path))

        let unzipDirectory = rootDirectory.appendingPathComponent("unzipped", isDirectory: true)
        try fileManager.createDirectory(at: unzipDirectory, withIntermediateDirectories: false)
        defer {
            try? fileManager.removeItem(at: unzipDirectory)
        }

        try fileManager.unzipItem(at: exportArchiveURL, to: unzipDirectory)

        let summaryURL = try #require(try findSummaryFileURL(in: unzipDirectory, fileManager: fileManager))
        let summaryContent = try String(contentsOf: summaryURL, encoding: .utf8)
        #expect(summaryContent.contains("Telocare Muse diagnostics export summary"))
        #expect(summaryContent.contains("session.muse"))
        #expect(summaryContent.contains("decisions.ndjson"))
        #expect(summaryContent.contains("manifest.json"))
        #expect(summaryContent.contains("diagnostics.log"))

        let extractedSessionURL = unzipDirectory.appendingPathComponent("session.muse")
        let extractedDecisionsURL = unzipDirectory.appendingPathComponent("decisions.ndjson")
        let extractedManifestURL = unzipDirectory.appendingPathComponent("manifest.json")
        let extractedLogURL = unzipDirectory.appendingPathComponent("diagnostics.log")

        #expect(fileManager.fileExists(atPath: extractedSessionURL.path))
        #expect(fileManager.fileExists(atPath: extractedDecisionsURL.path))
        #expect(fileManager.fileExists(atPath: extractedManifestURL.path))
        #expect(fileManager.fileExists(atPath: extractedLogURL.path))

        let exportedSessionData = try Data(contentsOf: extractedSessionURL)
        let sourceSessionData = try Data(contentsOf: sessionFileURL)
        #expect(exportedSessionData == sourceSessionData)

        let exportedManifestData = try Data(contentsOf: extractedManifestURL)
        let sourceManifestData = try Data(contentsOf: manifestFileURL)
        #expect(exportedManifestData == sourceManifestData)

        let exportedDecisionsData = try Data(contentsOf: extractedDecisionsURL)
        let sourceDecisionsData = try Data(contentsOf: decisionsFileURL)
        #expect(exportedDecisionsData == sourceDecisionsData)

        let exportedLogData = try Data(contentsOf: extractedLogURL)
        let sourceLogData = try Data(contentsOf: logFileURL)
        #expect(exportedLogData == sourceLogData)
    }

    @Test func makeThrowsWhenNoInputFilesExist() {
        #expect(throws: MuseDiagnosticsExportBundleError.noFiles) {
            _ = try MuseDiagnosticsExportBundle.make(
                fileURLs: [URL(fileURLWithPath: "/tmp/does-not-exist.muse")]
            )
        }
    }

    private func findSummaryFileURL(in directory: URL, fileManager: FileManager) throws -> URL? {
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return contents.first { $0.lastPathComponent.hasPrefix("muse-diagnostics-export-summary-") }
    }
}
