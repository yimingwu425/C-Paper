import XCTest
@testable import CPaperNativeApp

@MainActor
final class ModelTests: XCTestCase {
    func testRouteMetadata() {
        XCTAssertEqual(AppRoute.search.title, "搜索")
        XCTAssertEqual(AppRoute.batch.symbolName, "tray.and.arrow.down")
    }

    func testDownloadCounts() {
        let model = AppModel()
        model.downloads = [
            DownloadTaskItem(id: 0, filename: "a.pdf", ftype: "QP", label: "Paper 1", year: "2023", savePath: "/tmp/a.pdf", status: .done, error: "", errorType: ""),
            DownloadTaskItem(id: 1, filename: "b.pdf", ftype: "MS", label: "Paper 1", year: "2023", savePath: "/tmp/b.pdf", status: .failed, error: "boom", errorType: "network"),
            DownloadTaskItem(id: 2, filename: "c.pdf", ftype: "QP", label: "Paper 2", year: "2023", savePath: "/tmp/c.pdf", status: .downloading, error: "", errorType: "")
        ]

        XCTAssertEqual(model.completedDownloadCount, 1)
        XCTAssertEqual(model.failedDownloadCount, 1)
        XCTAssertEqual(model.activeDownloadCount, 1)
    }

    func testSettingsCodingKeysRoundTrip() throws {
        let settings = DownloadSettings(
            theme: "light",
            saveDirectory: "/tmp/cpaper",
            includeMarkSchemes: false,
            rate: 6,
            threads: 3,
            mergeFolders: true,
            proxyURL: "http://127.0.0.1:7890",
            lastSubject: "9709",
            lastMode: "batch",
            duplicateMode: .missing
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DownloadSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }
}
