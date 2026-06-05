import Foundation
import XCTest
@testable import CPaperNativeApp

final class DownloadManagerTests: XCTestCase {
    func testDownloadManagerCancelsPendingAndActiveItems() async throws {
        let root = makeTemporaryDownloadDirectory()
        let manager = DownloadManager { _, partialURL in
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try Data("late".utf8).write(to: partialURL)
        }
        let group = NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: "s24",
            number: "12",
            paperGroup: 1,
            qp: makeDownloadComponent(filename: "a.pdf", type: "QP", sy: "s24"),
            ms: nil,
            extras: [
                makeDownloadComponent(filename: "b.pdf", type: "QP", sy: "s24"),
                makeDownloadComponent(filename: "c.pdf", type: "QP", sy: "s24")
            ]
        )

        try await manager.start(groups: [group], saveDirectory: root, options: makeDownloadOptions(threads: 1))
        try await Task.sleep(nanoseconds: 50_000_000)
        await manager.cancel()
        let snapshot = await manager.status()
        let items = await manager.items()

        XCTAssertEqual(snapshot.phase, "done")
        XCTAssertEqual(snapshot.cancelled, 3)
        XCTAssertTrue(items.allSatisfy { $0.status == .cancelled })
    }

    func testDownloadManagerRetriesFailuresBeforeSucceeding() async throws {
        let root = makeTemporaryDownloadDirectory()
        let attempts = AttemptCounter()
        let manager = DownloadManager { _, partialURL in
            let current = await attempts.next()

            if current < 3 {
                throw NSError(domain: "DownloadManagerTests", code: current, userInfo: [NSLocalizedDescriptionKey: "temporary"])
            }

            try Data("ok".utf8).write(to: partialURL)
        }

        try await manager.start(
            groups: [NativePaperGroup(
                sourceID: .frankcie,
                subjectCode: "9709",
                sy: "s24",
                number: "12",
                paperGroup: 1,
                qp: makeDownloadComponent(filename: "retry.pdf", type: "QP", sy: "s24"),
                ms: nil,
                extras: []
            )],
            saveDirectory: root,
            options: makeDownloadOptions(threads: 1)
        )
        let snapshot = try await waitForDownloadCompletion(manager)

        XCTAssertEqual(snapshot.success, 1)
        XCTAssertEqual(snapshot.failed, 0)
        let attemptCount = await attempts.value
        XCTAssertEqual(attemptCount, 3)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("2024/QP/retry.pdf")), "ok")
    }

    func testDownloadManagerWaitsForCircuitBreakerRecoveryBeforeRetrying() async throws {
        let root = makeTemporaryDownloadDirectory()
        let attempts = CircuitBreakerAttemptRecorder()
        let recoveryTimeout: Duration = .milliseconds(75)
        let manager = DownloadManager(download: { _, partialURL in
            let current = await attempts.next()

            if current <= 5 {
                throw NSError(domain: "DownloadManagerTests", code: current, userInfo: [NSLocalizedDescriptionKey: "temporary"])
            }

            try Data("ok".utf8).write(to: partialURL)
        }, circuitBreakerRecoveryTimeout: recoveryTimeout)
        let group = NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: "s24",
            number: "12",
            paperGroup: 1,
            qp: makeDownloadComponent(filename: "breaker-1.pdf", type: "QP", sy: "s24"),
            ms: nil,
            extras: [
                makeDownloadComponent(filename: "breaker-2.pdf", type: "QP", sy: "s24"),
                makeDownloadComponent(filename: "breaker-3.pdf", type: "QP", sy: "s24"),
                makeDownloadComponent(filename: "breaker-4.pdf", type: "QP", sy: "s24"),
                makeDownloadComponent(filename: "breaker-5.pdf", type: "QP", sy: "s24"),
                makeDownloadComponent(filename: "breaker-6.pdf", type: "QP", sy: "s24")
            ]
        )

        try await manager.start(groups: [group], saveDirectory: root, options: makeDownloadOptions(threads: 1))
        let snapshot = try await waitForDownloadCompletion(manager)
        let attemptCount = await attempts.value
        let recordedRecoveryDelay = await attempts.recoveryDelay
        let recoveryDelay = try XCTUnwrap(recordedRecoveryDelay)

        XCTAssertEqual(snapshot.success, 6)
        XCTAssertEqual(snapshot.failed, 0)
        XCTAssertEqual(snapshot.message, "完成 (6/6 成功) (经过 1 轮重试)")
        XCTAssertEqual(attemptCount, 11)
        XCTAssertGreaterThanOrEqual(recoveryDelay, 0.07)
    }

    func testDownloadManagerWaitsWhenCircuitBreakerOpensAtRetryBoundary() async throws {
        let root = makeTemporaryDownloadDirectory()
        let attempts = CircuitBreakerAttemptRecorder()
        let recoveryTimeout: Duration = .milliseconds(75)
        let manager = DownloadManager(download: { _, partialURL in
            let current = await attempts.next()

            if current <= 5 {
                throw NSError(domain: "DownloadManagerTests", code: current, userInfo: [NSLocalizedDescriptionKey: "temporary"])
            }

            try Data("ok".utf8).write(to: partialURL)
        }, circuitBreakerRecoveryTimeout: recoveryTimeout)
        let group = NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: "s24",
            number: "12",
            paperGroup: 1,
            qp: makeDownloadComponent(filename: "breaker-boundary-1.pdf", type: "QP", sy: "s24"),
            ms: nil,
            extras: [
                makeDownloadComponent(filename: "breaker-boundary-2.pdf", type: "QP", sy: "s24"),
                makeDownloadComponent(filename: "breaker-boundary-3.pdf", type: "QP", sy: "s24"),
                makeDownloadComponent(filename: "breaker-boundary-4.pdf", type: "QP", sy: "s24"),
                makeDownloadComponent(filename: "breaker-boundary-5.pdf", type: "QP", sy: "s24")
            ]
        )

        try await manager.start(groups: [group], saveDirectory: root, options: makeDownloadOptions(threads: 1))
        let snapshot = try await waitForDownloadCompletion(manager)
        let attemptCount = await attempts.value
        let recordedRecoveryDelay = await attempts.recoveryDelay
        let recoveryDelay = try XCTUnwrap(recordedRecoveryDelay)

        XCTAssertEqual(snapshot.success, 5)
        XCTAssertEqual(snapshot.failed, 0)
        XCTAssertEqual(snapshot.message, "完成 (5/5 成功) (经过 1 轮重试)")
        XCTAssertEqual(attemptCount, 10)
        XCTAssertGreaterThanOrEqual(recoveryDelay, 0.07)
    }

    func testDownloadManagerStatusCountsDoneAndFailedItems() async throws {
        let root = makeTemporaryDownloadDirectory()
        let manager = DownloadManager { sourceURL, partialURL in
            if sourceURL.lastPathComponent == "bad.pdf" {
                throw NSError(domain: "DownloadManagerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "permanent"])
            }
            try Data("ok".utf8).write(to: partialURL)
        }
        let group = NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: "s25",
            number: "12",
            paperGroup: 1,
            qp: makeDownloadComponent(filename: "good.pdf", type: "QP", sy: "s25", url: URL(string: "https://example.test/good.pdf")!),
            ms: nil,
            extras: [
                makeDownloadComponent(filename: "bad.pdf", type: "QP", sy: "s25", url: URL(string: "https://example.test/bad.pdf")!)
            ]
        )

        try await manager.start(groups: [group], saveDirectory: root, options: makeDownloadOptions(threads: 2))
        let snapshot = try await waitForDownloadCompletion(manager)
        let items = await manager.items()

        XCTAssertEqual(snapshot.total, 2)
        XCTAssertEqual(snapshot.done, 2)
        XCTAssertEqual(snapshot.success, 1)
        XCTAssertEqual(snapshot.failed, 1)
        XCTAssertEqual(items.filter { $0.status == .done }.count, 1)
        XCTAssertEqual(items.filter { $0.status == .failed }.count, 1)
    }

    func testDownloadManagerRefreshesEasyPaperTokenBeforeDownload() async throws {
        let root = makeTemporaryDownloadDirectory()
        let observed = DownloadURLRecorder()
        let manager = DownloadManager { sourceURL, partialURL in
            await observed.set(sourceURL)
            try Data("ok".utf8).write(to: partialURL)
        }
        let filePath = "CAIE|AS and A Level|Mathematics (9709)|2023|Summer|9709_s23_qp_12.pdf"
        let staleURL = URL(string: "https://mirror.easy-paper.test/paperdownload/dir_v3/stale-token")!
            .withEasyPaperFilePath(filePath)
        let group = NativePaperGroup(
            sourceID: .easyPaper,
            subjectCode: "9709",
            sy: "s23",
            number: "12",
            paperGroup: 1,
            qp: PaperComponent(
                sourceID: .easyPaper,
                filename: "9709_s23_qp_12.pdf",
                url: staleURL,
                paperType: "QP",
                subjectCode: "9709",
                sy: "s23",
                number: "12",
                label: nil
            ),
            ms: nil,
            extras: []
        )

        try await manager.start(groups: [group], saveDirectory: root, options: makeDownloadOptions(threads: 1))
        let snapshot = try await waitForDownloadCompletion(manager)
        let recordedURL = await observed.value
        let sourceURL = try XCTUnwrap(recordedURL)

        XCTAssertEqual(snapshot.success, 1)
        XCTAssertEqual(sourceURL.host, "mirror.easy-paper.test")
        XCTAssertTrue(sourceURL.path.contains("/paperdownload/dir_v3/"))
        XCTAssertNotEqual(sourceURL.lastPathComponent, "stale-token")
        XCTAssertNil(sourceURL.fragment)
    }

    func testNativeBackendRecordsHistoryAndSkipsPreviouslyDownloadedFiles() async throws {
        let storageRoot = makeTemporaryDownloadDirectory()
        let saveRoot = makeTemporaryDownloadDirectory()
        let paths = try AppStoragePaths(rootURL: storageRoot)
        try FileManager.default.createDirectory(at: paths.appSupportDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: paths.migrationMarkerURL)
        let historyRecorder = NativeHistoryRecorder(paths: paths)
        let manager = DownloadManager { _, partialURL in
            try Data("ok".utf8).write(to: partialURL)
        } completionRecorder: { task in
            await historyRecorder.record(task)
        }
        let service = try NativeBackendService(paths: paths, downloadManager: manager)
        let group = NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: "s23",
            number: "12",
            paperGroup: 1,
            qp: makeDownloadComponent(filename: "9709_s23_qp_12.pdf", type: "QP"),
            ms: nil,
            extras: []
        )

        let first = try await service.startDownload(
            groups: [group],
            saveDirectory: saveRoot.path,
            options: makeDownloadOptions(threads: 1)
        )
        XCTAssertEqual(first.total, 1)
        _ = try await waitForDownloadCompletion(manager)

        let history = DownloadHistoryStore(paths: paths).load()
        XCTAssertEqual(history.map(\.filename), ["9709_s23_qp_12.pdf"])

        let second = try await service.startDownload(
            groups: [group],
            saveDirectory: saveRoot.path,
            options: makeDownloadOptions(threads: 1, duplicateMode: .skip)
        )

        XCTAssertEqual(second.total, 0)
        XCTAssertEqual(second.skipped, 1)
    }
}
