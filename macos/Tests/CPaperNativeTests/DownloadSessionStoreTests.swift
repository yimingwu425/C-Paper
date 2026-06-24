import XCTest
@testable import CPaperNativeApp

final class DownloadSessionStoreTests: XCTestCase {
    func testRestoreInterruptedSessionBacksUpCorruptSessionAndReturnsDefaultDocument() throws {
        let storageRoot = makeTemporaryDownloadDirectory()
        try FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
        let paths = try AppStoragePaths(rootURL: storageRoot)
        try Data("{".utf8).write(to: paths.downloadSessionURL)

        let store = DownloadSessionStore(
            store: JSONFileStore(
                url: paths.downloadSessionURL,
                defaultValue: DownloadSessionDocument(),
                now: { Date(timeIntervalSince1970: 1_700_000_000) }
            )
        )

        let restored = try store.restoreInterruptedSession()

        XCTAssertEqual(restored.document, DownloadSessionDocument())
        XCTAssertEqual(restored.cleanedPartialCount, 0)
        XCTAssertEqual(restored.resumedFailureCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.downloadSessionURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: "\(paths.downloadSessionURL.path).corrupt.1700000000"
            )
        )
    }

    func testRestoreInterruptedSessionOnlyMarksActiveItemsFailedAndKeepsExistingTerminalStates() throws {
        let storageRoot = makeTemporaryDownloadDirectory()
        let saveRoot = makeTemporaryDownloadDirectory()
        try FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
        let paths = try AppStoragePaths(rootURL: storageRoot)
        let sessionStore = DownloadSessionStore(paths: paths)

        let doneURL = saveRoot
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent("done.pdf", isDirectory: false)
        let failedURL = saveRoot
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent("failed.pdf", isDirectory: false)
        let interruptedURL = saveRoot
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent("interrupted.pdf", isDirectory: false)
        try FileManager.default.createDirectory(
            at: interruptedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let stalePartialURL = interruptedURL.deletingLastPathComponent()
            .appendingPathComponent("interrupted.pdf.part.stale", isDirectory: false)
        try Data("partial".utf8).write(to: stalePartialURL)

        let tasks = [
            DownloadDestinationTask(
                id: 0,
                component: makeDownloadComponent(filename: "done.pdf", type: "QP", sy: "s24"),
                filename: "done.pdf",
                ftype: "QP",
                label: "Done",
                year: "2024",
                saveURL: doneURL
            ),
            DownloadDestinationTask(
                id: 1,
                component: makeDownloadComponent(filename: "failed.pdf", type: "QP", sy: "s24"),
                filename: "failed.pdf",
                ftype: "QP",
                label: "Failed",
                year: "2024",
                saveURL: failedURL
            ),
            DownloadDestinationTask(
                id: 2,
                component: makeDownloadComponent(filename: "interrupted.pdf", type: "QP", sy: "s24"),
                filename: "interrupted.pdf",
                ftype: "QP",
                label: "Interrupted",
                year: "2024",
                saveURL: interruptedURL
            )
        ]
        let items = [
            DownloadTaskItem(
                id: 0,
                filename: "done.pdf",
                ftype: "QP",
                label: "Done",
                year: "2024",
                savePath: doneURL.path,
                status: .done,
                error: "",
                errorType: nil,
                progressFraction: 1
            ),
            DownloadTaskItem(
                id: 1,
                filename: "failed.pdf",
                ftype: "QP",
                label: "Failed",
                year: "2024",
                savePath: failedURL.path,
                status: .failed,
                error: "旧错误",
                errorType: .network,
                progressFraction: nil
            ),
            DownloadTaskItem(
                id: 2,
                filename: "interrupted.pdf",
                ftype: "QP",
                label: "Interrupted",
                year: "2024",
                savePath: interruptedURL.path,
                status: .downloading,
                error: "",
                errorType: nil,
                progressFraction: 0.4
            )
        ]
        try sessionStore.save(
            DownloadSessionDocument(
                tasks: tasks,
                items: items,
                snapshot: DownloadStatusSnapshot(
                    phase: .running,
                    done: 1,
                    total: 3,
                    success: 1,
                    message: "下载中... (1/3)",
                    failed: 1,
                    cancelled: 0,
                    skipped: 0
                ),
                options: makeDownloadOptions(threads: 1),
                proxyURL: "http://127.0.0.1:9090"
            )
        )

        let restored = try sessionStore.restoreInterruptedSession()
        let restoredItems = restored.document.items.sorted { $0.id < $1.id }

        XCTAssertEqual(restored.cleanedPartialCount, 1)
        XCTAssertEqual(restored.resumedFailureCount, 1)
        XCTAssertEqual(restored.document.options?.threads, 1)
        XCTAssertEqual(restored.document.proxyURL, "http://127.0.0.1:9090")
        XCTAssertEqual(restoredItems.map(\.status), [.done, .failed, .failed])
        XCTAssertEqual(restoredItems[1].error, "旧错误")
        XCTAssertEqual(restoredItems[1].errorType, .network)
        XCTAssertEqual(restoredItems[2].error, "上次下载在应用退出前中断，请重试")
        XCTAssertEqual(restoredItems[2].errorType, .interrupted)
        XCTAssertEqual(restored.document.snapshot.phase, .done)
        XCTAssertEqual(restored.document.snapshot.done, 3)
        XCTAssertEqual(restored.document.snapshot.total, 3)
        XCTAssertEqual(restored.document.snapshot.success, 1)
        XCTAssertEqual(restored.document.snapshot.failed, 2)
        XCTAssertEqual(restored.document.snapshot.cancelled, 0)
        XCTAssertEqual(restored.document.snapshot.skipped, 0)
        XCTAssertEqual(restored.document.snapshot.message, "上次下载在退出时中断，可重试失败项")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stalePartialURL.path))
    }
}
