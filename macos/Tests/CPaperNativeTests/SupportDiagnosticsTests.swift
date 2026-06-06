import XCTest
@testable import CPaperNativeApp

final class SupportDiagnosticsTests: XCTestCase {
    func testRedactsProxyCredentialsEasyPaperTokensQuerySecretsAndHomePaths() {
        let home = NSHomeDirectory()
        let input = """
        proxy=http://alice:secret@127.0.0.1:7890
        source=https://easypaper.com/paperdownload/dir_v3/raw-token?token=abc123&password=s3cr3t
        file=\(home)/Downloads/C-Paper/private.pdf
        """

        let redacted = SupportDiagnostic.redact(input)

        XCTAssertFalse(redacted.contains("alice:secret"))
        XCTAssertFalse(redacted.contains("raw-token"))
        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("s3cr3t"))
        XCTAssertFalse(redacted.contains(home))
        XCTAssertTrue(redacted.contains("http://<redacted>@127.0.0.1:7890"))
        XCTAssertTrue(redacted.contains("/paperdownload/dir_v3/<redacted>"))
        XCTAssertTrue(redacted.contains("token=<redacted>"))
        XCTAssertTrue(redacted.contains("password=<redacted>"))
        XCTAssertTrue(redacted.contains("~/Downloads/C-Paper/private.pdf"))
    }

    func testStoreWritesLatestDiagnosticReportUnderSupportDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperSupportDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = try AppStoragePaths(rootURL: root)
        let store = SupportDiagnosticsStore(paths: paths)
        let diagnostic = SupportDiagnostic(
            context: .download,
            message: "下载失败",
            details: [
                SupportDiagnosticDetail(label: "Proxy", value: "http://alice:secret@127.0.0.1:7890")
            ],
            supportDirectoryPath: store.directoryURL.path,
            createdAt: Date(timeIntervalSince1970: 0)
        )

        let reportURL = try store.write(diagnostic)
        let report = try String(contentsOf: reportURL)

        XCTAssertEqual(reportURL, store.directoryURL.appendingPathComponent("latest-diagnostic.txt"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertTrue(report.contains("Area: 下载"))
        XCTAssertTrue(report.contains("Message: 下载失败"))
        XCTAssertTrue(report.contains("Proxy: http://<redacted>@127.0.0.1:7890"))
        XCTAssertFalse(report.contains("alice:secret"))
    }
}
