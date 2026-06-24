import Foundation
import XCTest
@testable import CPaperNativeApp

final class DownloadManagerTests: XCTestCase {
    func testDownloadManagerRetriesRateLimitedItemAfterServerDelay() async throws {
        let root = makeTemporaryDownloadDirectory()
        let attempts = AttemptCounter()
        let manager = DownloadManager(sharedTransfer: { _, partialURL, _, _ in
            let current = await attempts.next()
            if current == 1 {
                throw NetworkClientError.rateLimited(statusCode: 429, retryAfter: 0.12)
            }

            try Data("ok".utf8).write(to: partialURL)
        })

        let startedAt = ContinuousClock.now
        try await manager.start(
            groups: [makeSingleComponentGroup(filename: "retry-429.pdf", sy: "s24")],
            saveDirectory: root,
            options: makeDownloadOptions(threads: 1)
        )

        let waitingSnapshot = try await waitForDownloadMessage("服务器限流，等待后自动重试...", in: manager)
        let snapshot = try await waitForDownloadCompletion(manager)
        let elapsed = startedAt.duration(to: .now)
        let attemptCount = await attempts.value

        XCTAssertEqual(waitingSnapshot.message, "服务器限流，等待后自动重试...")
        XCTAssertEqual(snapshot.success, 1)
        XCTAssertEqual(snapshot.failed, 0)
        XCTAssertEqual(attemptCount, 2)
        XCTAssertGreaterThanOrEqual(seconds(elapsed), 0.1)
    }

    func testDownloadManagerUsesInjectedDefaultCooldownWhenRetryAfterMissing() async throws {
        let root = makeTemporaryDownloadDirectory()
        let attempts = AttemptCounter()
        let manager = DownloadManager(
            sharedTransfer: { _, partialURL, _, _ in
                let current = await attempts.next()
                if current == 1 {
                    throw NetworkClientError.rateLimited(statusCode: 429, retryAfter: nil)
                }

                try Data("ok".utf8).write(to: partialURL)
            },
            defaultRateLimitCooldown: .milliseconds(40),
            minimumRateLimitCooldown: .milliseconds(10),
            maximumRateLimitCooldown: .milliseconds(40)
        )

        let startedAt = ContinuousClock.now
        try await manager.start(
            groups: [makeSingleComponentGroup(filename: "retry-default-429.pdf", sy: "s24")],
            saveDirectory: root,
            options: makeDownloadOptions(threads: 1)
        )

        _ = try await waitForDownloadMessage("服务器限流，等待后自动重试...", in: manager)
        let snapshot = try await waitForDownloadCompletion(manager)
        let elapsed = startedAt.duration(to: .now)
        let attemptCount = await attempts.value

        XCTAssertEqual(snapshot.success, 1)
        XCTAssertEqual(snapshot.failed, 0)
        XCTAssertEqual(attemptCount, 2)
        XCTAssertGreaterThanOrEqual(seconds(elapsed), 0.035)
    }

    func testDownloadManagerStopsConcurrentWorkersFromStartingNewRequestsDuringCooldown() async throws {
        let root = makeTemporaryDownloadDirectory()
        let attempts = AttemptCounter()
        let starts = TimedEventRecorder()
        let manager = DownloadManager(
            sharedTransfer: { sourceURL, partialURL, _, _ in
                let filename = sourceURL.lastPathComponent
                await starts.record(filename)
                let current = await attempts.next()
                if current == 1 {
                    throw NetworkClientError.rateLimited(statusCode: 429, retryAfter: 0.2)
                }

                try Data(filename.utf8).write(to: partialURL)
            },
            minimumRateLimitCooldown: .milliseconds(200),
            maximumRateLimitCooldown: .milliseconds(200)
        )
        let group = NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: "s24",
            number: "12",
            paperGroup: 1,
            qp: makeDownloadComponent(filename: "cooldown-1.pdf", type: "QP", sy: "s24"),
            ms: nil,
            extras: [
                makeDownloadComponent(filename: "cooldown-2.pdf", type: "QP", sy: "s24"),
                makeDownloadComponent(filename: "cooldown-3.pdf", type: "QP", sy: "s24")
            ]
        )

        try await manager.start(groups: [group], saveDirectory: root, options: makeDownloadOptions(rate: 20, threads: 3))
        _ = try await waitForDownloadMessage("服务器限流，等待后自动重试...", in: manager)
        try await Task.sleep(nanoseconds: 50_000_000)
        let startedNames = await starts.names()

        XCTAssertEqual(startedNames, ["cooldown-1.pdf"])

        let snapshot = try await waitForDownloadCompletion(manager)
        let recordedSecondOffset = await starts.offset(for: "cooldown-2.pdf")
        let secondOffset = try XCTUnwrap(recordedSecondOffset)

        XCTAssertEqual(snapshot.success, 3)
        XCTAssertEqual(snapshot.failed, 0)
        XCTAssertGreaterThanOrEqual(seconds(secondOffset), 0.18)
    }

    func testDownloadManagerDoesNotMassFailAfterRecoverableRateLimit() async throws {
        let root = makeTemporaryDownloadDirectory()
        let attempts = AttemptCounter()
        let manager = DownloadManager(
            sharedTransfer: { sourceURL, partialURL, _, _ in
                let filename = sourceURL.lastPathComponent
                let current = await attempts.next()
                if filename == "recoverable-1.pdf", current == 1 {
                    throw NetworkClientError.rateLimited(statusCode: 429, retryAfter: 0.05)
                }

                try Data(filename.utf8).write(to: partialURL)
            },
            minimumRateLimitCooldown: .milliseconds(50),
            maximumRateLimitCooldown: .milliseconds(50)
        )
        let group = NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: "s24",
            number: "12",
            paperGroup: 1,
            qp: makeDownloadComponent(filename: "recoverable-1.pdf", type: "QP", sy: "s24"),
            ms: nil,
            extras: [
                makeDownloadComponent(filename: "recoverable-2.pdf", type: "QP", sy: "s24"),
                makeDownloadComponent(filename: "recoverable-3.pdf", type: "QP", sy: "s24"),
                makeDownloadComponent(filename: "recoverable-4.pdf", type: "QP", sy: "s24")
            ]
        )

        try await manager.start(groups: [group], saveDirectory: root, options: makeDownloadOptions(threads: 4))
        let snapshot = try await waitForDownloadCompletion(manager)
        let items = await manager.items()

        XCTAssertEqual(snapshot.total, 4)
        XCTAssertEqual(snapshot.success, 4)
        XCTAssertEqual(snapshot.failed, 0)
        XCTAssertTrue(items.allSatisfy { $0.status == .done })
    }

    func testDownloadManagerTracksSharedTransferProgress() async throws {
        let root = makeTemporaryDownloadDirectory()
        let progress = DownloadProgressCoordinator()
        let manager = DownloadManager(sharedTransfer: { _, partialURL, _, reportProgress in
            await reportProgress(0)
            await reportProgress(0.5)
            await progress.record(0.5)
            await progress.waitForFinishPermission()
            try Data("ok".utf8).write(to: partialURL)
            await reportProgress(1)
        })

        try await manager.start(
            groups: [makeSingleComponentGroup(filename: "progress.pdf", sy: "s24")],
            saveDirectory: root,
            options: makeDownloadOptions(threads: 1)
        )
        await progress.waitForHalfProgress()

        let midItems = await manager.items()
        let midItem = try XCTUnwrap(midItems.first)
        XCTAssertEqual(midItem.status, .downloading)
        XCTAssertEqual(try XCTUnwrap(midItem.progressFraction), 0.5, accuracy: 0.0001)

        await progress.allowFinish()
        let snapshot = try await waitForDownloadCompletion(manager)
        let doneItems = await manager.items()
        let doneItem = try XCTUnwrap(doneItems.first)
        let doneProgress = try XCTUnwrap(doneItem.progressFraction)

        XCTAssertEqual(snapshot.success, 1)
        XCTAssertEqual(doneItem.status, .done)
        XCTAssertEqual(doneProgress, 1, accuracy: 0.0001)
    }

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

        XCTAssertEqual(snapshot.phase, .done)
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

    func testDownloadManagerCanRetryRecoverableFailedItemsAfterCompletion() async throws {
        let root = makeTemporaryDownloadDirectory()
        let attempts = AttemptCounter()
        let manager = DownloadManager { sourceURL, partialURL in
            if sourceURL.lastPathComponent == "bad.pdf" {
                let current = await attempts.next()
                if current <= 4 {
                    throw URLError(.notConnectedToInternet)
                }
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

        try await manager.start(groups: [group], saveDirectory: root, options: makeDownloadOptions(threads: 1))
        let firstSnapshot = try await waitForDownloadCompletion(manager)
        let firstItems = await manager.items()

        XCTAssertEqual(firstSnapshot.success, 1)
        XCTAssertEqual(firstSnapshot.failed, 1)
        XCTAssertEqual(firstItems.first(where: { $0.filename == "bad.pdf" })?.recoveryAction, .retryNow)

        let didStartRetry = await manager.retryRecoverableFailedItems()
        XCTAssertTrue(didStartRetry)

        let retrySnapshot = try await waitForDownloadCompletion(manager)
        let retryItems = await manager.items()
        let attemptCount = await attempts.value

        XCTAssertEqual(retrySnapshot.success, 2)
        XCTAssertEqual(retrySnapshot.failed, 0)
        XCTAssertEqual(retryItems.map(\.status), [.done, .done])
        XCTAssertEqual(attemptCount, 5)
    }

    func testDownloadManagerCanRetryCompletedItemsNeedingRepair() async throws {
        let root = makeTemporaryDownloadDirectory()
        let attempts = AttemptCounter()
        let manager = DownloadManager { _, partialURL in
            let current = await attempts.next()
            try Data("attempt-\(current)".utf8).write(to: partialURL)
        }
        let group = NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: "s25",
            number: "12",
            paperGroup: 1,
            qp: makeDownloadComponent(filename: "repair.pdf", type: "QP", sy: "s25", url: URL(string: "https://example.test/repair.pdf")!),
            ms: nil,
            extras: []
        )
        let savedFileURL = root
            .appendingPathComponent("2025", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent("repair.pdf", isDirectory: false)

        try await manager.start(groups: [group], saveDirectory: root, options: makeDownloadOptions(threads: 1))
        _ = try await waitForDownloadCompletion(manager)

        XCTAssertEqual(try String(contentsOf: savedFileURL), "attempt-1")

        let didStartRetry = await manager.retryCompletedItemsNeedingRepair(ids: [0])
        XCTAssertTrue(didStartRetry)

        let retrySnapshot = try await waitForDownloadCompletion(manager)
        let attemptCount = await attempts.value

        XCTAssertEqual(retrySnapshot.success, 1)
        XCTAssertEqual(retrySnapshot.failed, 0)
        XCTAssertEqual(try String(contentsOf: savedFileURL), "attempt-2")
        XCTAssertEqual(attemptCount, 2)
    }

    func testDownloadManagerRefreshesEasyPaperTokenBeforeDownload() async throws {
        let root = makeTemporaryDownloadDirectory()
        let observed = ControlledDownloadCoordinator()
        let manager = DownloadManager(sharedTransfer: { sourceURL, partialURL, proxyURL, _ in
            await observed.recordTransfer(url: sourceURL, proxyURL: proxyURL)
            try Data("ok".utf8).write(to: partialURL)
        })
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

        try await manager.start(
            groups: [group],
            saveDirectory: root,
            options: makeDownloadOptions(threads: 1),
            proxyURL: "http://127.0.0.1:7890"
        )
        let snapshot = try await waitForDownloadCompletion(manager)
        let transfers = await observed.transfers()
        let sourceURL = try XCTUnwrap(transfers.first?.url)

        XCTAssertEqual(snapshot.success, 1)
        XCTAssertEqual(sourceURL.host, "mirror.easy-paper.test")
        XCTAssertTrue(sourceURL.path.contains("/paperdownload/dir_v3/"))
        XCTAssertNotEqual(sourceURL.lastPathComponent, "stale-token")
        XCTAssertNil(sourceURL.fragment)
        XCTAssertEqual(transfers.map(\.proxyURL), ["http://127.0.0.1:7890"])
    }

    func testDownloadManagerStartWhileRunningIgnoresLateCompletionFromPreviousRun() async throws {
        let root = makeTemporaryDownloadDirectory()
        let coordinator = ControlledDownloadCoordinator()
        let manager = DownloadManager { sourceURL, partialURL in
            let filename = sourceURL.lastPathComponent
            await coordinator.markStarted(filename)
            await coordinator.waitUntilAllowed(filename)
            try Data("payload-\(filename)".utf8).write(to: partialURL)
        }

        try await manager.start(
            groups: [makeSingleComponentGroup(filename: "old.pdf", sy: "s23")],
            saveDirectory: root,
            options: makeDownloadOptions(threads: 1)
        )
        await coordinator.waitUntilStarted("old.pdf")

        try await manager.start(
            groups: [makeSingleComponentGroup(filename: "new.pdf", sy: "s24")],
            saveDirectory: root,
            options: makeDownloadOptions(threads: 1)
        )
        let itemsAfterRestart = await manager.items()

        XCTAssertEqual(itemsAfterRestart.map(\.filename), ["new.pdf"])

        await coordinator.allow("old.pdf")
        await coordinator.waitUntilStarted("new.pdf")
        await coordinator.allow("new.pdf")

        let snapshot = try await waitForDownloadCompletion(manager)
        let items = await manager.items()

        XCTAssertEqual(snapshot.total, 1)
        XCTAssertEqual(snapshot.success, 1)
        XCTAssertEqual(snapshot.failed, 0)
        XCTAssertEqual(snapshot.cancelled, 0)
        XCTAssertEqual(items.map(\.filename), ["new.pdf"])
        XCTAssertEqual(items.map(\.status), [.done])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("2023/QP/old.pdf").path
            )
        )
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("2024/QP/new.pdf")),
            "payload-new.pdf"
        )
    }

    func testDownloadManagerCancelThenStartIgnoresLateCompletionFromCancelledRun() async throws {
        let root = makeTemporaryDownloadDirectory()
        let coordinator = ControlledDownloadCoordinator()
        let manager = DownloadManager { sourceURL, partialURL in
            let filename = sourceURL.lastPathComponent
            await coordinator.markStarted(filename)
            await coordinator.waitUntilAllowed(filename)
            try Data("payload-\(filename)".utf8).write(to: partialURL)
        }

        try await manager.start(
            groups: [makeSingleComponentGroup(filename: "cancelled.pdf", sy: "s23")],
            saveDirectory: root,
            options: makeDownloadOptions(threads: 1)
        )
        await coordinator.waitUntilStarted("cancelled.pdf")

        await manager.cancel()
        let cancelledSnapshot = await manager.status()
        XCTAssertEqual(cancelledSnapshot.phase, .done)
        XCTAssertEqual(cancelledSnapshot.cancelled, 1)

        try await manager.start(
            groups: [makeSingleComponentGroup(filename: "fresh.pdf", sy: "s24")],
            saveDirectory: root,
            options: makeDownloadOptions(threads: 1)
        )

        await coordinator.allow("cancelled.pdf")
        await coordinator.waitUntilStarted("fresh.pdf")
        await coordinator.allow("fresh.pdf")

        let snapshot = try await waitForDownloadCompletion(manager)
        let items = await manager.items()

        XCTAssertEqual(snapshot.total, 1)
        XCTAssertEqual(snapshot.success, 1)
        XCTAssertEqual(snapshot.cancelled, 0)
        XCTAssertEqual(items.map(\.filename), ["fresh.pdf"])
        XCTAssertEqual(items.map(\.status), [.done])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("2023/QP/cancelled.pdf").path
            )
        )
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("2024/QP/fresh.pdf")),
            "payload-fresh.pdf"
        )
    }

    func testDownloadManagerRestoresInterruptedSessionAsRetryableFailureAndRetriesIt() async throws {
        let storageRoot = makeTemporaryDownloadDirectory()
        let saveRoot = makeTemporaryDownloadDirectory()
        let paths = try AppStoragePaths(rootURL: storageRoot)
        let sessionStore = DownloadSessionStore(paths: paths)
        let saveURL = saveRoot
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent("interrupted.pdf", isDirectory: false)
        try FileManager.default.createDirectory(
            at: saveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let partialURL = saveURL.deletingLastPathComponent()
            .appendingPathComponent("interrupted.pdf.part.stale", isDirectory: false)
        try Data("partial".utf8).write(to: partialURL)

        let task = DownloadDestinationTask(
            id: 0,
            component: makeDownloadComponent(filename: "interrupted.pdf", type: "QP", sy: "s24"),
            filename: "interrupted.pdf",
            ftype: "QP",
            label: "Paper 1",
            year: "2024",
            saveURL: saveURL
        )
        try sessionStore.save(
            DownloadSessionDocument(
                tasks: [task],
                items: [
                    DownloadTaskItem(
                        id: 0,
                        filename: "interrupted.pdf",
                        ftype: "QP",
                        label: "Paper 1",
                        year: "2024",
                        savePath: saveURL.path,
                        status: .downloading,
                        error: "",
                        errorType: nil,
                        progressFraction: 0.5
                    )
                ],
                snapshot: DownloadStatusSnapshot(
                    phase: .running,
                    done: 0,
                    total: 1,
                    success: 0,
                    message: "下载中... (0/1)",
                    failed: 0,
                    cancelled: 0,
                    skipped: 0
                ),
                options: makeDownloadOptions(threads: 1),
                proxyURL: "http://127.0.0.1:9090"
            )
        )

        let observed = ControlledDownloadCoordinator()
        let manager = DownloadManager(
            sharedTransfer: { sourceURL, partialURL, proxyURL, _ in
                await observed.recordTransfer(url: sourceURL, proxyURL: proxyURL)
                try Data("restored".utf8).write(to: partialURL)
            },
            sessionStore: sessionStore
        )

        let restoredSnapshot = await manager.status()
        let restoredItems = await manager.items()
        let recoverySummary = await manager.consumeRecoverySummary()
        let secondRecoverySummary = await manager.consumeRecoverySummary()

        XCTAssertEqual(restoredSnapshot.phase, .done)
        XCTAssertEqual(restoredSnapshot.failed, 1)
        XCTAssertEqual(restoredSnapshot.message, "上次下载在退出时中断，可重试失败项")
        XCTAssertEqual(restoredItems.map(\.status), [.failed])
        XCTAssertEqual(restoredItems.first?.errorType, .interrupted)
        XCTAssertEqual(
            recoverySummary,
            DownloadSessionRecoverySummary(cleanedPartialCount: 1, resumedFailureCount: 1)
        )
        XCTAssertNil(secondRecoverySummary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))

        let didRetry = await manager.retryRecoverableFailedItems()
        XCTAssertTrue(didRetry)

        let snapshot = try await waitForDownloadCompletion(manager)
        let items = await manager.items()
        let transfers = await observed.transfers()
        let persisted = sessionStore.load()

        XCTAssertEqual(snapshot.success, 1)
        XCTAssertEqual(snapshot.failed, 0)
        XCTAssertEqual(items.map(\.status), [.done])
        XCTAssertEqual(transfers.map(\.proxyURL), ["http://127.0.0.1:9090"])
        XCTAssertEqual(transfers.map { $0.url.lastPathComponent }, ["interrupted.pdf"])
        XCTAssertEqual(try String(contentsOf: saveURL), "restored")
        XCTAssertEqual(persisted.items.map(\.status), [.done])
        XCTAssertEqual(persisted.snapshot.success, 1)
        XCTAssertEqual(persisted.snapshot.failed, 0)
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
            options: makeDownloadOptions(threads: 1),
            proxyURL: ""
        )
        XCTAssertEqual(first.total, 1)
        _ = try await waitForDownloadCompletion(manager)

        let history = DownloadHistoryStore(paths: paths).load()
        XCTAssertEqual(history.map(\.filename), ["9709_s23_qp_12.pdf"])

        let second = try await service.startDownload(
            groups: [group],
            saveDirectory: saveRoot.path,
            options: makeDownloadOptions(threads: 1, duplicateMode: .skip),
            proxyURL: ""
        )

        XCTAssertEqual(second.total, 0)
        XCTAssertEqual(second.skipped, 1)
    }

    func testNativeBackendStartDownloadPassesProxyURLToSharedTransferPath() async throws {
        let storageRoot = makeTemporaryDownloadDirectory()
        let saveRoot = makeTemporaryDownloadDirectory()
        let paths = try AppStoragePaths(rootURL: storageRoot)
        try FileManager.default.createDirectory(at: paths.appSupportDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: paths.migrationMarkerURL)
        let observed = ControlledDownloadCoordinator()
        let manager = DownloadManager(sharedTransfer: { sourceURL, partialURL, proxyURL, _ in
            await observed.recordTransfer(url: sourceURL, proxyURL: proxyURL)
            try Data("ok".utf8).write(to: partialURL)
        })
        let service = try NativeBackendService(paths: paths, downloadManager: manager)

        let result = try await service.startDownload(
            groups: [makeSingleComponentGroup(filename: "proxied.pdf", sy: "s24")],
            saveDirectory: saveRoot.path,
            options: makeDownloadOptions(threads: 1),
            proxyURL: "http://127.0.0.1:9090"
        )
        XCTAssertEqual(result.total, 1)

        let snapshot = try await waitForDownloadCompletion(manager)
        let transfers = await observed.transfers()

        XCTAssertEqual(snapshot.success, 1)
        XCTAssertEqual(transfers.map(\.proxyURL), ["http://127.0.0.1:9090"])
        XCTAssertEqual(transfers.map { $0.url.lastPathComponent }, ["proxied.pdf"])
    }

    private func makeSingleComponentGroup(filename: String, sy: String) -> NativePaperGroup {
        NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: sy,
            number: "12",
            paperGroup: 1,
            qp: makeDownloadComponent(filename: filename, type: "QP", sy: sy),
            ms: nil,
            extras: []
        )
    }
}
