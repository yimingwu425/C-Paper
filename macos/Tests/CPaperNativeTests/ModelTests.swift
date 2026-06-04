import XCTest
@testable import CPaperNativeApp

@MainActor
final class ModelTests: XCTestCase {
    func testRouteMetadata() {
        XCTAssertEqual(AppRoute.search.title, "搜索")
        XCTAssertEqual(AppRoute.batch.symbolName, "square.stack.3d.down.right")
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

    func testManualSubjectCodeActsAsFallbackWhenSubjectListIsUnavailable() {
        let model = AppModel()
        model.selectedSubject = nil
        model.manualSubjectCode = "9709"

        XCTAssertTrue(model.hasSearchSubject)
        XCTAssertEqual(model.activeSubject?.code, "9709")
        XCTAssertEqual(model.activeSubject?.name, "手动输入 9709")
    }

    func testSelectedSubjectTakesPriorityOverManualSubjectCode() {
        let model = AppModel()
        model.selectedSubject = Subject(code: "9701", name: "Chemistry")
        model.manualSubjectCode = "9709"

        XCTAssertEqual(model.activeSubject?.code, "9701")
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
            duplicateMode: .missing,
            sourceMode: .pastPapers
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DownloadSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }
}
