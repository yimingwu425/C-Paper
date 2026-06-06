import Foundation

final class SupportDiagnosticsStore: @unchecked Sendable {
    let directoryURL: URL
    private let fileManager: FileManager

    init(paths: AppStoragePaths, fileManager: FileManager = .default) {
        self.directoryURL = paths.appSupportDirectory.appendingPathComponent("Support", isDirectory: true)
        self.fileManager = fileManager
    }

    func write(_ diagnostic: SupportDiagnostic) throws -> URL {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let reportURL = directoryURL.appendingPathComponent("latest-diagnostic.txt", isDirectory: false)
        let diagnosticWithURL = diagnostic.withReportURL(reportURL)
        try diagnosticWithURL.reportText.write(to: reportURL, atomically: true, encoding: .utf8)
        return reportURL
    }
}
