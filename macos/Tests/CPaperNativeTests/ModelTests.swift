import AppKit
import PDFKit
import XCTest
@testable import CPaperNativeApp

@MainActor
final class ModelTests: XCTestCase {
    func testRouteMetadata() {
        XCTAssertEqual(AppRoute.search.title, "搜索")
        XCTAssertEqual(AppRoute.batch.symbolName, "square.stack.3d.down.right")
    }

    func testDownloadCounts() {
        let model = try! makeBasicModel()
        model.downloads = [
            DownloadTaskItem(id: 0, filename: "a.pdf", ftype: "QP", label: "Paper 1", year: "2023", savePath: "/tmp/a.pdf", status: .done, error: "", errorType: nil),
            DownloadTaskItem(id: 1, filename: "b.pdf", ftype: "MS", label: "Paper 1", year: "2023", savePath: "/tmp/b.pdf", status: .failed, error: "boom", errorType: .network),
            DownloadTaskItem(id: 2, filename: "c.pdf", ftype: "QP", label: "Paper 2", year: "2023", savePath: "/tmp/c.pdf", status: .downloading, error: "", errorType: nil),
            DownloadTaskItem(id: 3, filename: "d.pdf", ftype: "QP", label: "Paper 3", year: "2023", savePath: "/tmp/d.pdf", status: .cancelled, error: "", errorType: .cancelled),
            DownloadTaskItem(id: 4, filename: "e.pdf", ftype: "QP", label: "Paper 4", year: "2023", savePath: "/tmp/e.pdf", status: .skipped, error: "", errorType: nil)
        ]

        XCTAssertEqual(model.completedDownloadCount, 2)
        XCTAssertEqual(model.failedDownloadCount, 1)
        XCTAssertEqual(model.cancelledDownloadCount, 1)
        XCTAssertEqual(model.skippedDownloadCount, 1)
        XCTAssertEqual(model.activeDownloadCount, 1)
    }

    func testRetryableFailedDownloadCountIncludesOnlyQueueRetryFailures() {
        let model = try! makeBasicModel()
        model.downloads = [
            DownloadTaskItem(id: 0, filename: "network.pdf", ftype: "QP", label: "Paper 1", year: "2023", savePath: "/tmp/network.pdf", status: .failed, error: "offline", errorType: .network),
            DownloadTaskItem(id: 1, filename: "limit.pdf", ftype: "QP", label: "Paper 2", year: "2023", savePath: "/tmp/limit.pdf", status: .failed, error: "429", errorType: .rateLimit),
            DownloadTaskItem(id: 2, filename: "interrupted.pdf", ftype: "QP", label: "Paper 3", year: "2023", savePath: "/tmp/interrupted.pdf", status: .failed, error: "app interrupted", errorType: .interrupted),
            DownloadTaskItem(id: 3, filename: "unknown.pdf", ftype: "QP", label: "Paper 4", year: "2023", savePath: "/tmp/unknown.pdf", status: .failed, error: "custom", errorType: .unknown),
            DownloadTaskItem(id: 4, filename: "cancelled.pdf", ftype: "QP", label: "Paper 5", year: "2023", savePath: "/tmp/cancelled.pdf", status: .cancelled, error: "用户取消", errorType: .cancelled)
        ]

        XCTAssertEqual(model.failedDownloadCount, 4)
        XCTAssertEqual(model.retryableFailedDownloadCount, 3)
        XCTAssertTrue(model.hasRetryableFailedDownloads)
    }

    func testDownloadRecoverySummaryExplainsInterruptedQueueWithoutStartupNoticeState() throws {
        let model = try makeBasicModel()
        model.downloads = [
            DownloadTaskItem(
                id: 0,
                filename: "interrupted.pdf",
                ftype: "QP",
                label: "Paper 1",
                year: "2024",
                savePath: "/tmp/interrupted.pdf",
                status: .failed,
                error: "上次下载在应用退出前中断，请重试",
                errorType: .interrupted
            )
        ]

        XCTAssertEqual(model.interruptedFailedDownloadCount, 1)
        XCTAssertEqual(
            model.downloadRecoverySummary,
            "当前队列包含 1 个从上次会话恢复的失败任务，可直接重试失败项。"
        )
    }

    func testInterruptedFailedDownloadItemCarriesRecoveredSessionWorkflowTag() {
        let item = DownloadTaskItem(
            id: 0,
            filename: "interrupted.pdf",
            ftype: "QP",
            label: "Paper 1",
            year: "2024",
            savePath: "/tmp/interrupted.pdf",
            status: .failed,
            error: "上次下载在应用退出前中断，请重试",
            errorType: .interrupted
        )

        XCTAssertEqual(item.workflowTag, .recoveredInterruptedSession)
        XCTAssertEqual(item.workflowTag?.title, "上次会话")
        XCTAssertEqual(item.workflowTag?.summary, "该任务来自上次中断后恢复的下载会话。")
    }

    func testOrdinaryFailedDownloadItemDoesNotCarryRecoveredSessionWorkflowTag() {
        let item = DownloadTaskItem(
            id: 0,
            filename: "network.pdf",
            ftype: "QP",
            label: "Paper 1",
            year: "2024",
            savePath: "/tmp/network.pdf",
            status: .failed,
            error: "offline",
            errorType: .network
        )

        XCTAssertNil(item.workflowTag)
    }

    func testDownloadIntegrityStateUsesRepairableAndInspectOnlyVariants() {
        XCTAssertEqual(DownloadTaskIntegrityState.missingFile.title, "文件丢失")
        XCTAssertTrue(DownloadTaskIntegrityState.missingFile.allowsRepairRetry)
        XCTAssertEqual(DownloadTaskIntegrityState.directoryPath.title, "路径异常")
        XCTAssertFalse(DownloadTaskIntegrityState.directoryPath.allowsRepairRetry)
    }

    func testDownloadQueuePhaseEncodesAndDecodesRoundTrip() throws {
        let snapshot = DownloadStatusSnapshot(
            phase: .running,
            done: 2,
            total: 4,
            success: 1,
            message: "running",
            failed: 1,
            cancelled: 0,
            skipped: 0
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DownloadStatusSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertTrue(decoded.isRunning)
    }

    func testDownloadTaskErrorTypeDecodesLegacyEmptyStringAndUnknownValue() throws {
        let legacyJSON = """
        {
          "id": 7,
          "filename": "9709_s24_qp_12.pdf",
          "ftype": "QP",
          "label": "Paper 1",
          "year": "2024",
          "save_path": "/tmp/9709_s24_qp_12.pdf",
          "status": "failed",
          "error": "boom",
          "error_type": "",
          "progress_fraction": null
        }
        """.data(using: .utf8)!
        let unknownJSON = """
        {
          "id": 8,
          "filename": "9709_s24_qp_13.pdf",
          "ftype": "QP",
          "label": "Paper 2",
          "year": "2024",
          "save_path": "/tmp/9709_s24_qp_13.pdf",
          "status": "failed",
          "error": "boom",
          "error_type": "new_type"
        }
        """.data(using: .utf8)!

        let legacyItem = try JSONDecoder().decode(DownloadTaskItem.self, from: legacyJSON)
        let unknownItem = try JSONDecoder().decode(DownloadTaskItem.self, from: unknownJSON)
        let roundTripData = try JSONEncoder().encode(
            DownloadTaskItem(
                id: 9,
                filename: "9709_s24_qp_14.pdf",
                ftype: "QP",
                label: "Paper 3",
                year: "2024",
                savePath: "/tmp/9709_s24_qp_14.pdf",
                status: .failed,
                error: "limited",
                errorType: .rateLimit
            )
        )
        let roundTripItem = try JSONDecoder().decode(DownloadTaskItem.self, from: roundTripData)

        XCTAssertNil(legacyItem.errorType)
        XCTAssertEqual(unknownItem.errorType, .unknown)
        XCTAssertEqual(roundTripItem.errorType, .rateLimit)
    }

    func testDownloadTaskProgressUsesFractionWhenAvailable() {
        let inFlight = DownloadTaskItem(
            id: 1,
            filename: "paper.pdf",
            ftype: "QP",
            label: "Paper 1",
            year: "2024",
            savePath: "/tmp/paper.pdf",
            status: .downloading,
            error: "",
            errorType: nil,
            progressFraction: 0.42
        )
        let belowRange = DownloadTaskItem(
            id: 2,
            filename: "low.pdf",
            ftype: "QP",
            label: "Paper 2",
            year: "2024",
            savePath: "/tmp/low.pdf",
            status: .downloading,
            error: "",
            errorType: nil,
            progressFraction: -0.5
        )
        let aboveRange = DownloadTaskItem(
            id: 3,
            filename: "high.pdf",
            ftype: "QP",
            label: "Paper 3",
            year: "2024",
            savePath: "/tmp/high.pdf",
            status: .downloading,
            error: "",
            errorType: nil,
            progressFraction: 1.5
        )
        let legacyStyle = DownloadTaskItem(
            id: 4,
            filename: "legacy.pdf",
            ftype: "QP",
            label: "Paper 4",
            year: "2024",
            savePath: "/tmp/legacy.pdf",
            status: .downloading,
            error: "",
            errorType: nil
        )

        XCTAssertEqual(inFlight.progress, 0.42, accuracy: 0.0001)
        XCTAssertEqual(belowRange.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(aboveRange.progress, 1, accuracy: 0.0001)
        XCTAssertEqual(legacyStyle.progress, 0.55, accuracy: 0.0001)
    }

    func testDownloadTaskMessageUsesTypedFailureSummaryBeforeRawError() {
        let rateLimited = DownloadTaskItem(
            id: 1,
            filename: "paper.pdf",
            ftype: "QP",
            label: "Paper 1",
            year: "2024",
            savePath: "/tmp/paper.pdf",
            status: .failed,
            error: "服务器触发限流（HTTP 429），请在 30 秒后重试。",
            errorType: .rateLimit
        )
        let network = DownloadTaskItem(
            id: 2,
            filename: "paper2.pdf",
            ftype: "QP",
            label: "Paper 2",
            year: "2024",
            savePath: "/tmp/paper2.pdf",
            status: .failed,
            error: "The Internet connection appears to be offline.",
            errorType: .network
        )
        let unknown = DownloadTaskItem(
            id: 3,
            filename: "paper3.pdf",
            ftype: "QP",
            label: "Paper 3",
            year: "2024",
            savePath: "/tmp/paper3.pdf",
            status: .failed,
            error: "custom backend failure",
            errorType: .unknown
        )
        let interrupted = DownloadTaskItem(
            id: 4,
            filename: "paper4.pdf",
            ftype: "QP",
            label: "Paper 4",
            year: "2024",
            savePath: "/tmp/paper4.pdf",
            status: .failed,
            error: "下载过程中应用退出",
            errorType: .interrupted
        )

        XCTAssertEqual(rateLimited.message, "服务器限流，请稍后重试")
        XCTAssertEqual(rateLimited.rawErrorMessage, "服务器触发限流（HTTP 429），请在 30 秒后重试。")
        XCTAssertEqual(rateLimited.recoveryAction, .retryLater)
        XCTAssertEqual(network.message, "网络错误，请稍后重试")
        XCTAssertEqual(network.recoveryAction, .retryNow)
        XCTAssertEqual(interrupted.message, "上次下载在应用退出前中断，请重试")
        XCTAssertEqual(interrupted.recoveryAction, .retryNow)
        XCTAssertEqual(unknown.message, "下载失败")
        XCTAssertEqual(unknown.rawErrorMessage, "custom backend failure")
        XCTAssertEqual(unknown.recoveryAction, .inspectDiagnostic)
    }

    func testDownloadTaskRecoveryActionReflectsCancelledAndSuccessfulStates() {
        let cancelled = DownloadTaskItem(
            id: 1,
            filename: "cancelled.pdf",
            ftype: "QP",
            label: "Paper 1",
            year: "2024",
            savePath: "/tmp/cancelled.pdf",
            status: .cancelled,
            error: "用户取消",
            errorType: .cancelled
        )
        let done = DownloadTaskItem(
            id: 2,
            filename: "done.pdf",
            ftype: "QP",
            label: "Paper 2",
            year: "2024",
            savePath: "/tmp/done.pdf",
            status: .done,
            error: "",
            errorType: nil
        )

        XCTAssertEqual(cancelled.recoveryAction, .restartIfNeeded)
        XCTAssertEqual(cancelled.recoveryAction.guidance, "如需继续请重新加入")
        XCTAssertEqual(done.recoveryAction, .none)
        XCTAssertNil(done.recoveryAction.guidance)
    }

    func testDownloadQueueSummaryMarksAllSkippedFilesAsProcessed() {
        let summary = DownloadQueueSummary(
            total: 3,
            processed: 3,
            success: 0,
            failed: 0,
            cancelled: 0,
            skipped: 3
        )

        XCTAssertEqual(summary.subtitle, "已处理 3/3 个文件，成功 0 个，失败 0 个，跳过 3 个")
    }

    func testDownloadQueueSummaryMarksAllFailedFilesAsProcessed() {
        let summary = DownloadQueueSummary(
            total: 4,
            processed: 4,
            success: 0,
            failed: 4,
            cancelled: 0,
            skipped: 0
        )

        XCTAssertEqual(summary.subtitle, "已处理 4/4 个文件，成功 0 个，失败 4 个")
    }

    func testManualSubjectCodeActsAsFallbackWhenSubjectListIsUnavailable() {
        let model = try! makeBasicModel()
        model.selectedSubject = nil
        model.manualSubjectCode = "9709"

        XCTAssertTrue(model.hasSearchSubject)
        XCTAssertEqual(model.activeSubject?.code, "9709")
        XCTAssertEqual(model.activeSubject?.name, "手动输入 9709")
    }

    func testSelectedSubjectTakesPriorityOverManualSubjectCode() {
        let model = try! makeBasicModel()
        model.selectedSubject = Subject(code: "9701", name: "Chemistry")
        model.manualSubjectCode = "9709"

        XCTAssertEqual(model.activeSubject?.code, "9701")
    }

    func testLoadSubjectsDoesNotSelectFirstSubjectWhenNoSavedSubjectExists() async throws {
        let subjects = [
            Subject(code: "9231", name: "Further Mathematics"),
            Subject(code: "9709", name: "Mathematics")
        ]
        let model = try makeModelWithCachedSubjects(subjects)

        await model.loadSubjects()

        XCTAssertEqual(model.subjects.map(\.code), ["9231", "9709"])
        XCTAssertNil(model.selectedSubject)
        XCTAssertEqual(model.manualSubjectCode, "")
        XCTAssertFalse(model.hasSearchSubject)
    }

    func testLoadSubjectsRestoresSavedSubjectWhenAvailable() async throws {
        let subjects = [
            Subject(code: "9231", name: "Further Mathematics"),
            Subject(code: "9709", name: "Mathematics")
        ]
        let model = try makeModelWithCachedSubjects(subjects)
        model.settings.lastSubject = "9709"

        await model.loadSubjects()

        XCTAssertEqual(model.selectedSubject, Subject(code: "9709", name: "Mathematics"))
        XCTAssertEqual(model.manualSubjectCode, "")
        XCTAssertTrue(model.hasSearchSubject)
    }

    func testHandleLoadSubjectsFailureUsesContextualSourceNoticeAndRestoresFallbackCode() throws {
        let model = try makeBasicModel()
        model.settings.sourceMode = .easyPaper
        model.settings.lastSubject = "9709"
        model.manualSubjectCode = ""
        model.selectedSubject = nil

        model.handleLoadSubjectsFailure(DiagnosticTestError(message: "加载科目失败"))
        if model.selectedSubject == nil, model.manualSubjectCode.isEmpty, !model.settings.lastSubject.isEmpty {
            model.manualSubjectCode = model.settings.lastSubject
        }

        XCTAssertEqual(model.sourceNotice?.level, .failure)
        XCTAssertEqual(model.sourceNotice?.action, .retryLoadSubjects)
        XCTAssertEqual(model.sourceNotice?.message, "加载科目失败")
        XCTAssertEqual(model.lastDiagnostic?.context, .sourceProvider)
        XCTAssertEqual(model.lastDiagnostic?.details.first?.value, "EasyPaper")
        XCTAssertEqual(model.manualSubjectCode, "9709")
        XCTAssertNil(model.errorMessage)
    }

    func testLoadSubjectsUsesManualCodeGuidanceWhenSelectedSourceLacksSubjectList() async throws {
        let model = try makeManualSubjectListUnsupportedModel(sourceID: .papaCambridge)
        model.settings.sourceMode = .papaCambridge
        model.settings.lastSubject = "9709"
        model.manualSubjectCode = ""
        model.selectedSubject = nil

        await model.loadSubjects()

        XCTAssertTrue(model.subjects.isEmpty)
        XCTAssertEqual(model.sourceNotice?.level, .failure)
        XCTAssertNil(model.sourceNotice?.action)
        XCTAssertEqual(model.sourceNotice?.message, "当前来源不支持科目列表，请直接手动输入科目代码或切换来源。")
        XCTAssertEqual(
            model.lastDiagnostic?.details,
            [
                SupportDiagnosticDetail(label: "Source Mode", value: "PapaCambridge"),
                SupportDiagnosticDetail(label: "Reason", value: "PapaCambridge 暂不支持科目列表")
            ]
        )
        XCTAssertEqual(model.manualSubjectCode, "9709")
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
    }

    func testHandleLoadSubjectsFailureUsesManualCodeGuidanceWhenSelectedSourceLacksSubjectList() throws {
        let model = try makeBasicModel()
        model.settings.sourceMode = .papaCambridge
        model.settings.lastSubject = ""
        model.manualSubjectCode = ""
        model.selectedSubject = nil

        model.handleLoadSubjectsFailure(
            PaperSourceError.sourceUnavailable("PapaCambridge 暂不支持科目列表")
        )

        XCTAssertEqual(model.sourceNotice?.level, .failure)
        XCTAssertNil(model.sourceNotice?.action)
        XCTAssertEqual(model.sourceNotice?.message, "当前来源不支持科目列表，请直接手动输入科目代码或切换来源。")
        XCTAssertEqual(model.lastDiagnostic?.context, .sourceProvider)
        XCTAssertEqual(
            model.lastDiagnostic?.details,
            [
                SupportDiagnosticDetail(label: "Source Mode", value: "PapaCambridge"),
                SupportDiagnosticDetail(label: "Reason", value: "PapaCambridge 暂不支持科目列表")
            ]
        )
        XCTAssertEqual(model.manualSubjectCode, "")
        XCTAssertNil(model.errorMessage)
    }

    func testAddFavoriteFailureUsesContextualFavoriteNoticeInsteadOfGlobalError() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperAddFavoriteFailureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let backend = try NativeBackendService(paths: AppStoragePaths(rootURL: root))
        let model = AppModel(backend: backend)
        let subject = Subject(code: "9997", name: "Failure Add Subject")
        model.selectedSubject = subject

        try FileManager.default.removeItem(at: root)
        FileManager.default.createFile(atPath: root.path, contents: Data("blocked".utf8))

        await model.addSelectedSubjectToFavorites()

        XCTAssertEqual(model.favoriteNotice?.message, model.lastDiagnostic?.message)
        XCTAssertEqual(model.lastDiagnostic?.context, .favorites)
        XCTAssertEqual(
            model.lastDiagnostic?.details,
            [
                SupportDiagnosticDetail(label: "Operation", value: "收藏"),
                SupportDiagnosticDetail(label: "Subject Code", value: "9997"),
                SupportDiagnosticDetail(label: "Subject Name", value: "Failure Add Subject")
            ]
        )
        XCTAssertEqual(model.favoriteNotice?.action, .retryAdd(subject: subject))
        XCTAssertNil(model.errorMessage)
    }

    func testRemoveFavoriteFailureUsesContextualFavoriteNoticeInsteadOfGlobalError() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRemoveFavoriteFailureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let backend = try NativeBackendService(paths: AppStoragePaths(rootURL: root))
        try backend.addFavorite(Subject(code: "9998", name: "Failure Remove Subject"))
        let model = AppModel(backend: backend)
        await model.loadFavorites()
        let subject = try XCTUnwrap(model.favorites.first { $0.code == "9998" })

        try FileManager.default.removeItem(at: root)
        FileManager.default.createFile(atPath: root.path, contents: Data("blocked".utf8))

        await model.removeFavorite(subject)

        XCTAssertEqual(model.favoriteNotice?.message, model.lastDiagnostic?.message)
        XCTAssertEqual(model.lastDiagnostic?.context, .favorites)
        XCTAssertEqual(
            model.lastDiagnostic?.details,
            [
                SupportDiagnosticDetail(label: "Operation", value: "移除收藏"),
                SupportDiagnosticDetail(label: "Subject Code", value: "9998"),
                SupportDiagnosticDetail(label: "Subject Name", value: "Failure Remove Subject")
            ]
        )
        XCTAssertEqual(model.favoriteNotice?.action, .retryRemove(subject: subject))
        XCTAssertTrue(model.favorites.contains { $0.code == "9998" })
        XCTAssertNil(model.errorMessage)
    }

    func testPerformFavoriteNoticeActionRetriesAddFavorite() async throws {
        let model = try makeBasicModel()
        let subject = Subject(code: "9999", name: "Retry Favorite Subject")
        model.favoriteNotice = FavoriteNotice(
            diagnostic: SupportDiagnostic(context: .favorites, message: "收藏失败"),
            action: .retryAdd(subject: subject)
        )

        await model.performFavoriteNoticeAction()

        XCTAssertNil(model.favoriteNotice)
        XCTAssertTrue(model.favorites.contains(subject))
        XCTAssertEqual(model.selectedSubject, subject)
        XCTAssertEqual(model.manualSubjectCode, "")
        XCTAssertNil(model.errorMessage)
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

    func testDownloadingUpdateStatusPreservesDestinationURLBeforeCompletion() {
        let url = URL(fileURLWithPath: "/tmp/C-Paper/Updates/C-Paper-Native.dmg")
        let status = UpdateStatus.downloading(
            UpdateDownloadState(
                release: AppUpdateRelease(
                    version: "6.0.4",
                    tagName: "v6.0.4",
                    name: "C-Paper Native 6.0.4",
                    htmlURL: URL(string: "https://example.com/release")!,
                    assetName: "C-Paper-Native.dmg",
                    downloadURL: URL(string: "https://example.com/C-Paper-Native.dmg")!
                ),
                progress: 0.5,
                destinationURL: url
            )
        )

        XCTAssertEqual(status.destinationURL, url)
        XCTAssertNil(status.downloadedURL)
        XCTAssertEqual(status.message, "正在下载更新 50%")
    }

    func testRestoredDownloadedUpdateStateCarriesPersistentRecoverySummary() {
        let state = DownloadedUpdateState(
            release: AppUpdateRelease(
                version: "6.0.4",
                tagName: "v6.0.4",
                name: "C-Paper Native 6.0.4",
                htmlURL: URL(string: "https://example.com/release")!,
                assetName: "C-Paper-Native.dmg",
                downloadURL: URL(string: "https://example.com/C-Paper-Native.dmg")!
            ),
            fileURL: URL(fileURLWithPath: "/tmp/C-Paper-Native.dmg"),
            installState: .requiresManualOpen,
            origin: .restoredArtifact
        )

        XCTAssertEqual(state.message, "已恢复本地更新 DMG，等待手动打开")
        XCTAssertEqual(
            state.persistentSummary,
            "当前更新包来自之前已下载的本地 DMG，不是本次会话刚下载的文件，可直接手动打开安装。"
        )
    }

    func testPreviewLoadStateCarriesLoadedURLAndFailureDiagnostic() {
        let loadedURL = URL(fileURLWithPath: "/tmp/preview.pdf")
        let diagnostic = SupportDiagnostic(context: .preview, message: "预览失败")
        let failure = PreviewFailureState(diagnostic: diagnostic, suggestsRedownload: true)

        let loadingState = PreviewLoadState.loading
        let loadedState = PreviewLoadState.loaded(loadedURL)
        let failedState = PreviewLoadState.failed(failure)

        XCTAssertTrue(loadingState.isLoading)
        XCTAssertNil(loadingState.localURL)
        XCTAssertNil(loadingState.failureDiagnostic)
        XCTAssertNil(loadingState.failureState)

        XCTAssertFalse(loadedState.isLoading)
        XCTAssertEqual(loadedState.localURL, loadedURL)
        XCTAssertNil(loadedState.failureDiagnostic)
        XCTAssertNil(loadedState.failureState)

        XCTAssertFalse(failedState.isLoading)
        XCTAssertNil(failedState.localURL)
        XCTAssertEqual(failedState.failureDiagnostic, diagnostic)
        XCTAssertEqual(failedState.failureState, failure)
    }

    func testSelectingNewPreviewResetsLoadStateAndRequest() throws {
        let model = try makeBasicModel()
        let first = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let second = makePaperFile(filename: "9709_s24_qp_13.pdf")
        model.selectedPreview = first
        model.previewLoadState = .loaded(URL(fileURLWithPath: "/tmp/\(first.filename)"))
        model.previewLoadRevision = 2

        model.selectedPreview = second

        XCTAssertEqual(model.previewLoadState, .idle)
        XCTAssertEqual(model.previewLoadRevision, 0)
        XCTAssertEqual(model.previewLoadRequest, PreviewLoadRequest(fileID: second.id, revision: 0))
    }

    func testCancelledPreviewLoadDoesNotRecordFailureDiagnostic() async throws {
        let coordinator = PreviewModelLoadCoordinator()
        let model = try makePreviewModel { sourceURL, destinationURL, _ in
            let filename = sourceURL.lastPathComponent
            await coordinator.recordStart(filename)
            await coordinator.waitUntilAllowed(filename)
            try Task.checkCancellation()
            try Data("preview".utf8).write(to: destinationURL)
        }
        model.selectedPreview = makePaperFile(filename: "9709_s24_qp_12.pdf")

        let task = Task {
            await model.loadSelectedPreviewIfNeeded()
        }
        await coordinator.waitUntilStarted("9709_s24_qp_12.pdf")

        XCTAssertTrue(model.previewLoadState.isLoading)
        task.cancel()
        await coordinator.allow("9709_s24_qp_12.pdf")
        await task.value

        XCTAssertEqual(model.previewLoadState, .idle)
        XCTAssertNil(model.latestDiagnostic(for: .preview))
        XCTAssertNil(model.errorMessage)
    }

    func testStalePreviewLoadCompletionDoesNotOverwriteNewerSelection() async throws {
        let coordinator = PreviewModelLoadCoordinator()
        let validPDFData = try makeValidPreviewPDFData()
        let model = try makePreviewModel { sourceURL, destinationURL, _ in
            let filename = sourceURL.lastPathComponent
            await coordinator.recordStart(filename)
            if filename == "9709_s24_qp_12.pdf" {
                await coordinator.waitUntilAllowed(filename)
            }
            try validPDFData.write(to: destinationURL)
        }
        let first = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let second = makePaperFile(filename: "9709_s24_qp_13.pdf")
        model.selectedPreview = first

        let firstTask = Task {
            await model.loadSelectedPreviewIfNeeded()
        }
        await coordinator.waitUntilStarted(first.filename)

        model.selectedPreview = second
        await model.loadSelectedPreviewIfNeeded()
        await coordinator.allow(first.filename)
        await firstTask.value

        let loadedURL = try XCTUnwrap(model.previewLoadState.localURL)
        XCTAssertEqual(model.selectedPreview, second)
        XCTAssertEqual(loadedURL.lastPathComponent, second.filename)
        XCTAssertNil(model.latestDiagnostic(for: .preview))
    }

    func testRevealPreviewFileWhenCachedFileIsMissingUsesPreviewFailureState() throws {
        let model = try makeBasicModel()
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperMissingPreview-\(UUID().uuidString).pdf")
        model.selectedPreview = file
        model.previewLoadState = .loaded(missingURL)

        model.revealPreviewFile()

        guard case let .failed(failure) = model.previewLoadState else {
            return XCTFail("Expected preview failure state after missing cached file")
        }
        let diagnostic = failure.diagnostic
        XCTAssertEqual(diagnostic.message, "预览文件已丢失，请重新加载预览。")
        XCTAssertEqual(
            diagnostic.details,
            [
                SupportDiagnosticDetail(label: "Filename", value: file.filename),
                SupportDiagnosticDetail(label: "Cached File", value: missingURL.path)
            ]
        )
        XCTAssertFalse(failure.suggestsRedownload)
        XCTAssertEqual(model.lastDiagnostic?.context, .preview)
        XCTAssertNil(model.errorMessage)
    }

    func testPreviewLoadFailureRemovesUnreadableManagedCacheFileAndUsesRetryableFailure() async throws {
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let model = try makePreviewModel { _, destinationURL, _ in
            try Data("not a pdf".utf8).write(to: destinationURL)
        }
        model.selectedPreview = file

        await model.loadSelectedPreviewIfNeeded()

        guard case let .failed(failure) = model.previewLoadState else {
            return XCTFail("Expected preview failure state after unreadable cached preview file")
        }
        let diagnostic = failure.diagnostic
        XCTAssertEqual(diagnostic.message, "预览缓存已损坏，请重试预览。")
        XCTAssertTrue(
            diagnostic.details.contains(
                SupportDiagnosticDetail(label: "Recovery", value: "已移除损坏的预览缓存文件。")
            )
        )
        XCTAssertFalse(failure.suggestsRedownload)
        let cachedPreviewURL = URL(fileURLWithPath: model.backend.appSupportPath, isDirectory: true)
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("preview", isDirectory: true)
            .appendingPathComponent(file.filename)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedPreviewURL.path))
        XCTAssertEqual(model.lastDiagnostic?.context, .preview)
        XCTAssertNil(model.errorMessage)
    }

    func testPreviewLoadFailureKeepsUnreadableDownloadedFileAndUsesDownloadAwareMessage() async throws {
        let model = try makeBasicModel()
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let saveDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperUnreadableDownloadedPreview-\(UUID().uuidString)", isDirectory: true)
        let downloadedFileURL = saveDirectory
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent(file.filename)
        try FileManager.default.createDirectory(at: downloadedFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("still not a pdf".utf8).write(to: downloadedFileURL)
        defer { try? FileManager.default.removeItem(at: saveDirectory) }
        model.settings.saveDirectory = saveDirectory.path
        model.selectedPreview = file

        await model.loadSelectedPreviewIfNeeded()

        guard case let .failed(failure) = model.previewLoadState else {
            return XCTFail("Expected preview failure state after unreadable downloaded file")
        }
        let diagnostic = failure.diagnostic
        XCTAssertEqual(diagnostic.message, "预览文件无法打开，请重新下载或在浏览器中打开。")
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloadedFileURL.path))
        XCTAssertFalse(diagnostic.details.contains { $0.label == "Recovery" })
        XCTAssertTrue(failure.suggestsRedownload)
        XCTAssertEqual(model.lastDiagnostic?.context, .preview)
        XCTAssertNil(model.errorMessage)
    }

    func testRedownloadSelectedPreviewFileForcesOverwriteEvenWhenDuplicateModeWouldSkip() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperPreviewRepairModelTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let saveDirectory = pathsRoot.appendingPathComponent("Downloads", isDirectory: true)
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let downloadedFileURL = saveDirectory
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent(file.filename)
        try FileManager.default.createDirectory(at: downloadedFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: downloadedFileURL)
        let historyStore = DownloadHistoryStore(paths: paths)
        try historyStore.record(
            filename: file.filename,
            label: file.label ?? "Paper 1",
            year: "2024",
            savePath: downloadedFileURL.path
        )
        let manager = DownloadManager(sharedTransfer: { _, partialURL, _, _ in
            try Data("repaired".utf8).write(to: partialURL)
        })
        let backend = try NativeBackendService(paths: paths, downloadManager: manager)
        let model = AppModel(backend: backend)
        model.settings.saveDirectory = saveDirectory.path
        model.settings.duplicateMode = .skip
        model.selectedPreview = file

        await model.loadSelectedPreviewIfNeeded()
        guard case let .failed(failure) = model.previewLoadState else {
            return XCTFail("Expected preview failure state after unreadable downloaded file")
        }
        XCTAssertTrue(failure.suggestsRedownload)

        await model.redownloadSelectedPreviewFile()
        var snapshot = await manager.status()
        for _ in 0..<200 where snapshot.isRunning {
            try await Task.sleep(nanoseconds: 25_000_000)
            snapshot = await manager.status()
        }

        XCTAssertEqual(snapshot.success, 1)
        XCTAssertEqual(snapshot.skipped, 0)
        XCTAssertEqual(try String(contentsOf: downloadedFileURL), "repaired")
    }

    func testRedownloadSelectedPreviewFileQueuesAutomaticPreviewRetryAfterSuccessfulRepair() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperPreviewRepairRetryModelTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let saveDirectory = pathsRoot.appendingPathComponent("Downloads", isDirectory: true)
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let downloadedFileURL = saveDirectory
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent(file.filename)
        try FileManager.default.createDirectory(at: downloadedFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: downloadedFileURL)
        let historyStore = DownloadHistoryStore(paths: paths)
        try historyStore.record(
            filename: file.filename,
            label: file.label ?? "Paper 1",
            year: "2024",
            savePath: downloadedFileURL.path
        )
        let coordinator = ControlledDownloadCoordinator()
        let validPDFData = try makeValidPreviewPDFData()
        let manager = DownloadManager(sharedTransfer: { sourceURL, partialURL, _, _ in
            let filename = sourceURL.lastPathComponent
            await coordinator.markStarted(filename)
            await coordinator.waitUntilAllowed(filename)
            try validPDFData.write(to: partialURL)
        })
        let backend = try NativeBackendService(paths: paths, downloadManager: manager)
        let model = AppModel(backend: backend)
        model.settings.saveDirectory = saveDirectory.path
        model.settings.duplicateMode = .skip
        model.selectedPreview = file

        await model.loadSelectedPreviewIfNeeded()
        guard case let .failed(failure) = model.previewLoadState else {
            return XCTFail("Expected preview failure state after unreadable downloaded file")
        }
        XCTAssertTrue(failure.suggestsRedownload)

        let repairTask = Task {
            await model.redownloadSelectedPreviewFile()
        }
        await coordinator.waitUntilStarted(file.filename)
        await repairTask.value

        XCTAssertEqual(model.pendingPreviewRepairFileID, file.id)
        XCTAssertEqual(model.previewLoadRevision, 0)

        await coordinator.allow(file.filename)
        var snapshot = await manager.status()
        for _ in 0..<200 where snapshot.isRunning {
            try await Task.sleep(nanoseconds: 25_000_000)
            snapshot = await manager.status()
        }

        await model.refreshDownloads()

        XCTAssertNil(model.pendingPreviewRepairFileID)
        XCTAssertEqual(model.previewLoadRevision, 1)
        XCTAssertEqual(model.previewLoadState, .idle)

        await model.loadSelectedPreviewIfNeeded()
        let loadedURL = try XCTUnwrap(model.previewLoadState.localURL)
        XCTAssertEqual(loadedURL, downloadedFileURL)
    }

    func testEditingSettingsDraftDoesNotMutateModelOrPersistenceUntilCommitted() async throws {
        let initialSettings = DownloadSettings(
            theme: "light",
            saveDirectory: "/tmp/original",
            includeMarkSchemes: true,
            rate: 5,
            threads: 4,
            mergeFolders: false,
            proxyURL: "",
            lastSubject: "9701",
            lastMode: AppRoute.search.rawValue,
            duplicateMode: .overwrite,
            sourceMode: .automatic
        )
        let model = try await makePersistentModel(initialSettings: initialSettings)

        var draft = model.settings
        draft.saveDirectory = "/tmp/updated"
        draft.proxyURL = "http://127.0.0.1:7890"
        draft.rate = 8
        draft.threads = 7
        draft.sourceMode = .easyPaper

        XCTAssertEqual(model.settings, initialSettings)
        XCTAssertEqual(model.backend.loadSettings(), initialSettings)
    }

    func testSavingSettingsDraftCommitsToModelAndPersistence() async throws {
        let initialSettings = DownloadSettings(
            theme: "light",
            saveDirectory: "/tmp/original",
            includeMarkSchemes: true,
            rate: 5,
            threads: 4,
            mergeFolders: false,
            proxyURL: "",
            lastSubject: "",
            lastMode: AppRoute.search.rawValue,
            duplicateMode: .overwrite,
            sourceMode: .automatic
        )
        let model = try await makePersistentModel(initialSettings: initialSettings)
        model.route = .batch
        model.selectedSubject = Subject(code: "9709", name: "Mathematics")

        var draft = model.settings
        draft.saveDirectory = "/tmp/updated"
        draft.proxyURL = "http://127.0.0.1:7890"
        draft.rate = 8
        draft.threads = 7
        draft.sourceMode = .easyPaper

        let didSave = await model.saveSettings(draft)
        XCTAssertTrue(didSave)

        var expectedSettings = draft
        expectedSettings.lastSubject = "9709"
        expectedSettings.lastMode = AppRoute.batch.rawValue

        XCTAssertEqual(model.settings, expectedSettings)
        XCTAssertEqual(model.backend.loadSettings(), expectedSettings)
        XCTAssertNil(model.settingsNotice)
    }

    func testSavingSettingsFailureKeepsDraftOutOfModelAndShowsContextualSettingsNotice() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperSettingsFailureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let backend = try NativeBackendService(paths: AppStoragePaths(rootURL: root))
        let model = AppModel(backend: backend)
        await model.loadSettings()

        try FileManager.default.removeItem(at: root)
        FileManager.default.createFile(atPath: root.path, contents: Data("blocked".utf8))

        let originalSettings = model.settings
        var draft = model.settings
        draft.saveDirectory = "/tmp/changed"
        draft.sourceMode = .easyPaper

        let didSave = await model.saveSettings(draft)

        XCTAssertFalse(didSave)
        XCTAssertEqual(model.settings, originalSettings)
        XCTAssertEqual(model.settingsNotice?.message, model.lastDiagnostic?.message)
        XCTAssertEqual(model.lastDiagnostic?.context, .settings)
        XCTAssertEqual(model.lastDiagnostic?.details.map(\.label), ["Save Directory", "Source Mode"])
        XCTAssertNil(model.errorMessage)
    }

    func testUsableSaveDirectoryURLExpandsTildeForExistingDirectory() throws {
        let model = try makeBasicModel()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRevealDirectoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .standardizedFileURL
        let standardizedDirectory = directory.standardizedFileURL
        let relativePath = standardizedDirectory.path.replacingOccurrences(
            of: homeDirectory.path,
            with: "~",
            options: [.anchored]
        )
        model.settings.saveDirectory = relativePath

        let usableDirectory = try XCTUnwrap(model.usableSaveDirectoryURL())

        XCTAssertEqual(usableDirectory.standardizedFileURL, standardizedDirectory)
    }

    func testUsableSaveDirectoryURLAcceptsMissingCreatableDirectory() throws {
        let model = try makeBasicModel()
        let missingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperCreatableDirectory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: missingDirectory) }
        model.settings.saveDirectory = missingDirectory.path

        let usableDirectory = try XCTUnwrap(model.usableSaveDirectoryURL())

        XCTAssertEqual(usableDirectory.standardizedFileURL, missingDirectory.standardizedFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingDirectory.path))
    }

    func testResolvedSaveDirectoryKeepsMissingCreatableConfiguredDirectory() async throws {
        let model = try makeBasicModel()
        let missingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperResolvedCreatableDirectory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: missingDirectory) }
        model.settings.saveDirectory = missingDirectory.path

        let resolvedDirectory = try await model.resolvedSaveDirectory()

        guard case let .ready(resolvedPath) = resolvedDirectory else {
            return XCTFail("Expected ready save-directory resolution")
        }
        XCTAssertEqual(resolvedPath, missingDirectory.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingDirectory.path))
    }

    func testRevealSaveDirectoryCreatesMissingConfiguredDirectory() throws {
        let model = try makeBasicModel()
        _ = model.recordDiagnostic(context: .preview, message: "stale")
        let missingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperMissingDirectory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: missingDirectory) }
        model.settings.saveDirectory = missingDirectory.path

        model.revealSaveDirectory()

        XCTAssertTrue(FileManager.default.fileExists(atPath: missingDirectory.path))
        XCTAssertNil(model.saveDirectoryNotice)
        XCTAssertNil(model.errorMessage)
    }

    func testRevealSaveDirectoryUsesContextualNoticeWhenPathIsAFile() throws {
        let model = try makeBasicModel()
        _ = model.recordDiagnostic(context: .preview, message: "stale")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRevealDirectoryFile-\(UUID().uuidString).txt", isDirectory: false)
        try Data("test".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        model.settings.saveDirectory = fileURL.path

        model.revealSaveDirectory()

        XCTAssertEqual(model.saveDirectoryNotice?.message, "下载文件夹当前不可用，请先在设置中选择有效的保存目录。")
        XCTAssertEqual(model.saveDirectoryNotice?.action, .openSettings)
        XCTAssertEqual(model.lastDiagnostic?.context, .saveDirectory)
        XCTAssertEqual(model.lastDiagnostic?.message, model.saveDirectoryNotice?.message)
        XCTAssertEqual(model.lastDiagnostic?.details.map(\.label), ["Save Directory", "Reason"])
        XCTAssertEqual(model.lastDiagnostic?.details.last?.value, "保存路径指向文件而不是文件夹。")
        XCTAssertNil(model.errorMessage)
    }

    func testPerformSaveDirectoryNoticeActionOpensSettings() throws {
        let model = try makeBasicModel()
        model.isSettingsPresented = false
        model.saveDirectoryNotice = SaveDirectoryNotice(
            diagnostic: SupportDiagnostic(context: .saveDirectory, message: "下载文件夹不存在"),
            action: .openSettings
        )

        model.performSaveDirectoryNoticeAction()

        XCTAssertTrue(model.isSettingsPresented)
    }

    func testSavingSettingsClearsSaveDirectoryNoticeOnSuccess() async throws {
        let initialSettings = DownloadSettings(
            theme: "light",
            saveDirectory: "/tmp/original",
            includeMarkSchemes: true,
            rate: 5,
            threads: 4,
            mergeFolders: false,
            proxyURL: "",
            lastSubject: "",
            lastMode: AppRoute.search.rawValue,
            duplicateMode: .overwrite,
            sourceMode: .automatic
        )
        let model = try await makePersistentModel(initialSettings: initialSettings)
        model.saveDirectoryNotice = SaveDirectoryNotice(
            diagnostic: SupportDiagnostic(context: .saveDirectory, message: "下载文件夹不存在"),
            action: .openSettings
        )

        var draft = model.settings
        draft.saveDirectory = "/tmp/updated"

        let didSave = await model.saveSettings(draft)

        XCTAssertTrue(didSave)
        XCTAssertNil(model.saveDirectoryNotice)
    }

    func testBackendErrorsCreateRedactedSupportDiagnosticReport() throws {
        let model = try makeBasicModel()
        let home = NSHomeDirectory()

        model.handleBackendError(
            DiagnosticTestError(
                message: "Preview failed at \(home)/Downloads/file.pdf via http://alice:secret@127.0.0.1:7890/paperdownload/dir_v3/raw-token?token=abc123"
            ),
            context: .preview,
            details: [
                SupportDiagnosticDetail(label: "Proxy", value: "http://alice:secret@127.0.0.1:7890"),
                SupportDiagnosticDetail(label: "Path", value: "\(home)/Downloads/file.pdf")
            ]
        )

        let diagnostic = try XCTUnwrap(model.lastDiagnostic)
        let reportURL = try XCTUnwrap(diagnostic.reportURL)
        let report = try String(contentsOf: reportURL)

        XCTAssertEqual(diagnostic.context, .preview)
        XCTAssertEqual(model.errorMessage, diagnostic.message)
        XCTAssertFalse(diagnostic.reportText.contains("alice:secret"))
        XCTAssertFalse(diagnostic.reportText.contains("raw-token"))
        XCTAssertFalse(diagnostic.reportText.contains("abc123"))
        XCTAssertFalse(diagnostic.reportText.contains(home))
        XCTAssertTrue(report.contains("Area: 预览"))
        XCTAssertTrue(report.contains("http://<redacted>@127.0.0.1:7890"))
        XCTAssertTrue(report.contains("~/Downloads/file.pdf"))
    }

    func testRevealSupportDirectoryUsesContextualNoticeWhenSupportPathCannotBecomeDirectory() throws {
        let model = try makeBasicModel()
        let supportPath = model.supportDirectoryPath
        let supportURL = URL(fileURLWithPath: supportPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: supportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: supportPath, contents: Data("blocked".utf8))

        model.revealSupportDirectory()

        XCTAssertEqual(model.supportDirectoryNotice?.message, "支持文件夹无法打开，请检查应用支持目录权限。")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.lastDiagnostic?.context, .supportDirectory)
        XCTAssertEqual(model.lastDiagnostic?.details.first, SupportDiagnosticDetail(label: "Support Directory", value: supportPath))
        XCTAssertEqual(model.lastDiagnostic?.details.last?.label, "Reason")
        XCTAssertFalse(model.lastDiagnostic?.details.last?.value.isEmpty ?? true)
    }

    func testRevealSupportDirectoryClearsStaleNoticeAfterSuccessfulReveal() throws {
        let model = try makeBasicModel()
        model.supportDirectoryNotice = SupportDirectoryNotice(
            diagnostic: SupportDiagnostic(context: .supportDirectory, message: "支持文件夹无法打开，请检查应用支持目录权限。")
        )

        model.revealSupportDirectory()

        XCTAssertNil(model.supportDirectoryNotice)
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.supportDirectoryPath))
    }

    func testHandleSearchFailureClearsStaleResultsAndPreviewSelection() throws {
        let model = try makeBasicModel()
        let subject = Subject(code: "9709", name: "Mathematics")
        model.searchResults = [makePaperFile(filename: "9709_s24_qp_12.pdf")]
        model.searchGroups = [model.backendGroup(for: makePaperFile(filename: "9709_s24_qp_12.pdf"))]
        model.expandedPaperComponents = ["12"]
        model.selectedPreview = makePaperFile(filename: "9709_s24_qp_12.pdf")
        model.sourceNotice = SourceNotice(
            diagnostic: SupportDiagnostic(context: .sourceProvider, message: "FrankCIE: 无结果"),
            level: .warning,
            action: nil
        )
        model.selectedYear = 2024
        model.selectedSeason = .jun
        model.settings.sourceMode = .pastPapers

        model.handleSearchFailure(DiagnosticTestError(message: "search failed"), selectedSubject: subject)

        XCTAssertTrue(model.searchResults.isEmpty)
        XCTAssertTrue(model.searchGroups.isEmpty)
        XCTAssertTrue(model.expandedPaperComponents.isEmpty)
        XCTAssertNil(model.selectedPreview)
        XCTAssertEqual(model.sourceNotice?.level, .failure)
        XCTAssertEqual(model.sourceNotice?.action, .retrySearch)
        XCTAssertEqual(model.sourceNotice?.message, "search failed")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.lastDiagnostic?.context, .sourceProvider)
    }

    func testHandleBatchPreviewFailureClearsStaleBatchResultsAndPreviewSelection() throws {
        let model = try makeBasicModel()
        let subject = Subject(code: "9709", name: "Mathematics")
        model.batchPreview = [makePaperFile(filename: "9709_s24_qp_12.pdf")]
        model.batchGroups = [model.backendGroup(for: makePaperFile(filename: "9709_s24_qp_12.pdf"))]
        model.selectedPreview = makePaperFile(filename: "9709_s24_qp_12.pdf")
        model.sourceNotice = SourceNotice(
            diagnostic: SupportDiagnostic(context: .sourceProvider, message: "EasyPaper: 失败"),
            level: .warning,
            action: nil
        )
        model.batchYearFrom = 2021
        model.batchYearTo = 2024
        model.settings.sourceMode = .easyPaper

        model.handleBatchPreviewFailure(DiagnosticTestError(message: "batch failed"), selectedSubject: subject)

        XCTAssertTrue(model.batchPreview.isEmpty)
        XCTAssertTrue(model.batchGroups.isEmpty)
        XCTAssertNil(model.selectedPreview)
        XCTAssertEqual(model.sourceNotice?.level, .failure)
        XCTAssertEqual(model.sourceNotice?.action, .retryBatchPreview)
        XCTAssertEqual(model.sourceNotice?.message, "batch failed")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.lastDiagnostic?.context, .sourceProvider)
    }

    func testPreviewBatchUsesRetryableFailureWhenAllBatchQueriesFail() async throws {
        let model = try makeBatchPreviewModel { query in
            throw PaperSourceError.sourceUnavailable("mock unavailable \(query.year ?? 0)")
        }
        let subject = Subject(code: "9709", name: "Mathematics")
        model.selectedSubject = subject
        model.batchYearFrom = 2023
        model.batchYearTo = 2024
        model.batchSeasons = [.jun]
        model.batchPaperGroups = [1]

        await model.previewBatch()

        XCTAssertTrue(model.batchPreview.isEmpty)
        XCTAssertTrue(model.batchGroups.isEmpty)
        XCTAssertEqual(model.sourceNotice?.level, .failure)
        XCTAssertEqual(model.sourceNotice?.action, .retryBatchPreview)
        XCTAssertTrue(model.sourceNotice?.message.contains("所选年份和季度均未能获取结果") ?? false)
        XCTAssertEqual(model.lastDiagnostic?.context, .sourceProvider)
        XCTAssertNil(model.errorMessage)
    }

    func testPreviewBatchKeepsPartialResultsAndWarningsWhenSomeQueriesFail() async throws {
        let model = try makeBatchPreviewModel { query in
            guard query.year == 2024 else {
                throw PaperSourceError.sourceUnavailable("mock unavailable \(query.year ?? 0)")
            }
            guard let parsed = PaperFilenameParser.parse("9709_s24_qp_12.pdf") else {
                throw DiagnosticTestError(message: "failed to parse batch preview fixture filename")
            }
            let component = PaperComponent.sourceComponent(
                sourceID: .frankcie,
                parsed: parsed,
                url: URL(string: "https://example.test/9709_s24_qp_12.pdf")!
            )
            return SourceSearchResult(sourceID: .frankcie, components: [component])
        }
        let subject = Subject(code: "9709", name: "Mathematics")
        model.selectedSubject = subject
        model.batchYearFrom = 2023
        model.batchYearTo = 2024
        model.batchSeasons = [.jun]
        model.batchPaperGroups = [1]
        model.selectedPreview = makePaperFile(filename: "9709_s24_qp_12.pdf")

        await model.previewBatch()

        XCTAssertEqual(model.batchGroups.count, 1)
        XCTAssertEqual(model.batchPreview.map(\.filename), ["9709_s24_qp_12.pdf"])
        XCTAssertNil(model.selectedPreview)
        XCTAssertEqual(model.sourceNotice?.level, .warning)
        XCTAssertNil(model.sourceNotice?.action)
        XCTAssertTrue(model.sourceNotice?.message.contains("2023/") ?? false)
        XCTAssertTrue(model.sourceNotice?.message.contains("所有来源均不可用") ?? false)
        XCTAssertEqual(model.lastDiagnostic?.context, .sourceProvider)
        XCTAssertNil(model.errorMessage)
    }

    func testPreviewBatchStoresAggregateSourceSummaryAndFallbackState() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperBatchPreviewSourceSummaryTests-\(UUID().uuidString)", isDirectory: true)
        let subject = Subject(code: "9709", name: "Mathematics")
        let parsed2023 = try XCTUnwrap(PaperFilenameParser.parse("9709_s23_qp_12.pdf"))
        let parsed2024 = try XCTUnwrap(PaperFilenameParser.parse("9709_s24_qp_12.pdf"))
        let easyComponent = PaperComponent.sourceComponent(
            sourceID: .easyPaper,
            parsed: parsed2023,
            url: URL(string: "https://example.test/9709_s23_qp_12.pdf")!
        )
        let frankComponent = PaperComponent.sourceComponent(
            sourceID: .frankcie,
            parsed: parsed2024,
            url: URL(string: "https://example.test/9709_s24_qp_12.pdf")!
        )
        let backend = try NativeBackendService(
            paths: AppStoragePaths(rootURL: pathsRoot),
            sourceRegistryBuilder: { _ in
                SourceRegistry(
                    sources: [
                        ModelTestStubSource(id: .frankcie) { query in
                            guard query.year == 2024 else {
                                throw PaperSourceError.sourceUnavailable("搜索超时（超过 12 秒）")
                            }
                            return SourceSearchResult(sourceID: .frankcie, components: [frankComponent])
                        },
                        ModelTestStubSource(id: .easyPaper) { query in
                            guard query.year == 2023 else {
                                throw PaperSourceError.sourceUnavailable("EasyPaper 不应处理该年份")
                            }
                            return SourceSearchResult(sourceID: .easyPaper, components: [easyComponent])
                        }
                    ],
                    automaticOrder: [.frankcie, .easyPaper]
                )
            }
        )
        let model = AppModel(backend: backend)
        model.selectedSubject = subject
        model.batchYearFrom = 2023
        model.batchYearTo = 2024
        model.batchSeasons = [.jun]
        model.batchPaperGroups = [1]

        await model.previewBatch()

        XCTAssertEqual(model.batchPreview.map(\.filename), ["9709_s23_qp_12.pdf", "9709_s24_qp_12.pdf"])
        XCTAssertEqual(model.batchPreviewSourceIDs, [.easyPaper, .frankcie])
        XCTAssertEqual(model.batchPreviewSuccessfulQueryCount, 2)
        XCTAssertEqual(model.batchPreviewAutomaticFallbackQueryCount, 1)
        XCTAssertEqual(
            model.batchPreviewSourceSummary,
            "本次预览成功获取 2 个年份/考季查询，结果来自 EasyPaper、FrankCIE，其中 1 次查询触发自动回退。"
        )
        XCTAssertEqual(model.sourceNotice?.level, .automaticFallback)
    }

    func testHandleBatchPreviewFailureClearsPreviousSourceSummary() throws {
        let model = try makeBasicModel()
        let file = makePaperFile(filename: "9709_s23_qp_12.pdf")
        model.batchPreview = [file]
        model.batchGroups = [model.backendGroup(for: file)]
        model.batchPreviewSourceIDs = [.easyPaper, .frankcie]
        model.batchPreviewSuccessfulQueryCount = 2
        model.batchPreviewAutomaticFallbackQueryCount = 1

        model.handleBatchPreviewFailure(
            DiagnosticTestError(message: "batch failed"),
            selectedSubject: Subject(code: "9709", name: "Mathematics")
        )

        XCTAssertTrue(model.batchPreviewSourceIDs.isEmpty)
        XCTAssertEqual(model.batchPreviewSuccessfulQueryCount, 0)
        XCTAssertEqual(model.batchPreviewAutomaticFallbackQueryCount, 0)
        XCTAssertNil(model.batchPreviewSourceSummary)
    }

    func testApplySourceWarningsShowsVisibleMessageAndDiagnostic() throws {
        let model = try makeBasicModel()

        model.applySourceWarnings([
            "FrankCIE: 无结果",
            "EasyPaper: 失败"
        ])

        XCTAssertEqual(model.sourceNotice?.level, .warning)
        XCTAssertNil(model.sourceNotice?.action)
        XCTAssertEqual(model.sourceNotice?.message, "FrankCIE: 无结果")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.lastDiagnostic?.context, .sourceProvider)
        XCTAssertEqual(model.sourceNotice?.diagnostic, model.lastDiagnostic)
        XCTAssertEqual(model.lastDiagnostic?.details.count, 2)
    }

    func testSearchWarningsPreferFallbackSummaryBeforeDetailedAttemptDiagnostics() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperSearchWarningSummaryTests-\(UUID().uuidString)", isDirectory: true)
        let subject = Subject(code: "9709", name: "Mathematics")
        let parsed = try XCTUnwrap(PaperFilenameParser.parse("9709_s23_qp_12.pdf"))
        let component = PaperComponent.sourceComponent(
            sourceID: .easyPaper,
            parsed: parsed,
            url: URL(string: "https://example.test/9709_s23_qp_12.pdf")!
        )
        let backend = try NativeBackendService(
            paths: AppStoragePaths(rootURL: pathsRoot),
            sourceRegistryBuilder: { _ in
                SourceRegistry(
                    sources: [
                        ModelTestStubSource(id: .frankcie) { _ in
                            throw PaperSourceError.sourceUnavailable("搜索超时（超过 12 秒）")
                        },
                        ModelTestStubSource(id: .easyPaper) { _ in
                            SourceSearchResult(sourceID: .easyPaper, components: [component])
                        }
                    ],
                    automaticOrder: [.frankcie, .easyPaper]
                )
            }
        )
        let settings = DownloadSettings()

        let payload = try await backend.search(subject: subject, year: 2023, season: .jun, settings: settings)

        XCTAssertEqual(payload.sourceID, .easyPaper)
        XCTAssertTrue(payload.usedAutomaticFallback)
        XCTAssertEqual(
            payload.warnings.first,
            "首选来源响应过慢或不可用，已自动切换到 EasyPaper，当前结果可继续使用。"
        )
        XCTAssertTrue(payload.warnings.dropFirst().first?.contains("FrankCIE: 搜索超时（超过 12 秒）") == true)
    }

    func testSearchStoresResultSourceSummaryAndFallbackState() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperSearchSourceSummaryModelTests-\(UUID().uuidString)", isDirectory: true)
        let subject = Subject(code: "9709", name: "Mathematics")
        let parsed = try XCTUnwrap(PaperFilenameParser.parse("9709_s23_qp_12.pdf"))
        let component = PaperComponent.sourceComponent(
            sourceID: .easyPaper,
            parsed: parsed,
            url: URL(string: "https://example.test/9709_s23_qp_12.pdf")!
        )
        let backend = try NativeBackendService(
            paths: AppStoragePaths(rootURL: pathsRoot),
            sourceRegistryBuilder: { _ in
                SourceRegistry(
                    sources: [
                        ModelTestStubSource(id: .frankcie) { _ in
                            throw PaperSourceError.sourceUnavailable("搜索超时（超过 12 秒）")
                        },
                        ModelTestStubSource(id: .easyPaper) { _ in
                            SourceSearchResult(sourceID: .easyPaper, components: [component])
                        }
                    ],
                    automaticOrder: [.frankcie, .easyPaper]
                )
            }
        )
        let model = AppModel(backend: backend)
        model.selectedSubject = subject
        model.selectedYear = 2023
        model.selectedSeason = .jun

        await model.search()

        XCTAssertEqual(model.searchResultSourceID, .easyPaper)
        XCTAssertTrue(model.searchUsedAutomaticFallback)
        XCTAssertEqual(
            model.searchResultSourceSummary,
            "当前结果来自 EasyPaper，系统已自动跳过更慢或不可用的前置来源。"
        )
        XCTAssertEqual(model.sourceNotice?.level, .automaticFallback)
    }

    func testSearchFailureClearsPreviousResultSourceSummary() throws {
        let model = try makeBasicModel()
        let file = makePaperFile(filename: "9709_s23_qp_12.pdf")
        model.searchResults = [file]
        model.searchGroups = [model.backendGroup(for: file)]
        model.searchResultSourceID = .easyPaper
        model.searchUsedAutomaticFallback = true

        model.handleSearchFailure(
            DiagnosticTestError(message: "search failed"),
            selectedSubject: Subject(code: "9709", name: "Mathematics")
        )

        XCTAssertNil(model.searchResultSourceID)
        XCTAssertFalse(model.searchUsedAutomaticFallback)
        XCTAssertNil(model.searchResultSourceSummary)
    }

    func testApplySourceWarningsUsesAutomaticFallbackNoticeLevelForFallbackSummary() throws {
        let model = try makeBasicModel()

        model.applySourceWarnings([
            "首选来源响应过慢或不可用，已自动切换到 EasyPaper，当前结果可继续使用。",
            "FrankCIE: 搜索超时（超过 12 秒）（耗时 12034 ms）"
        ])

        XCTAssertEqual(model.sourceNotice?.level, .automaticFallback)
        XCTAssertNil(model.sourceNotice?.action)
        XCTAssertEqual(model.sourceNotice?.message, "首选来源响应过慢或不可用，已自动切换到 EasyPaper，当前结果可继续使用。")
        XCTAssertEqual(model.lastDiagnostic?.context, .sourceProvider)
    }

    func testApplySourceWarningsClearsVisibleSourceDiagnosticWhenWarningsDisappear() throws {
        let model = try makeBasicModel()
        model.applySourceWarnings(["FrankCIE: 无结果"])

        model.applySourceWarnings([])

        XCTAssertNil(model.sourceNotice)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.lastDiagnostic?.context, .sourceProvider)
        XCTAssertEqual(model.lastDiagnostic?.message, "FrankCIE: 无结果")
    }

    func testApplySourceWarningsDoesNotClearUnrelatedVisibleError() throws {
        let model = try makeBasicModel()
        model.presentDiagnosticError("下载失败", context: .download)

        model.applySourceWarnings([])

        XCTAssertEqual(model.errorMessage, "下载失败")
        XCTAssertNil(model.sourceNotice)
        XCTAssertEqual(model.lastDiagnostic?.context, .download)
    }

    func testDismissSourceNoticeClearsVisibleSourceNotice() throws {
        let model = try makeBasicModel()
        model.sourceNotice = SourceNotice(
            diagnostic: SupportDiagnostic(context: .sourceProvider, message: "FrankCIE: 无结果"),
            level: .failure,
            action: .retrySearch
        )

        model.dismissSourceNotice()

        XCTAssertNil(model.sourceNotice)
    }

    func testHandleDownloadStartFailureUsesContextualDownloadNoticeInsteadOfGlobalError() throws {
        let model = try makeBasicModel()
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")

        model.handleDownloadStartFailure(
            DiagnosticTestError(message: "下载任务启动失败"),
            action: .retrySingleFileDownload(file: file, origin: .batch),
            details: [
                SupportDiagnosticDetail(label: "Filename", value: file.filename)
            ]
        )

        guard case let .retrySingleFileDownload(retryFile, origin)? = model.downloadNotice?.action else {
            return XCTFail("Expected retryable single-file download notice")
        }
        XCTAssertEqual(retryFile.filename, "9709_s24_qp_12.pdf")
        XCTAssertEqual(origin, .batch)
        XCTAssertEqual(model.downloadNotice?.message, "下载任务启动失败")
        XCTAssertEqual(model.lastDiagnostic?.context, .download)
        XCTAssertEqual(model.lastDiagnostic?.details.first?.label, "Filename")
        XCTAssertNil(model.errorMessage)
    }

    func testPerformDownloadNoticeActionRetriesSingleFileDownloadStart() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperSingleFileDownloadRetryTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let saveDirectory = pathsRoot.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        let manager = DownloadManager(
            sharedTransfer: { _, partialURL, _, _ in
                try Data("ok".utf8).write(to: partialURL)
            },
            sessionStore: DownloadSessionStore(paths: paths)
        )
        let backend = try NativeBackendService(paths: paths, downloadManager: manager)
        let model = AppModel(backend: backend)
        model.route = .search
        model.settings.saveDirectory = saveDirectory.path
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        model.downloadNotice = DownloadNotice(
            diagnostic: SupportDiagnostic(context: .download, message: "下载任务启动失败"),
            action: .retrySingleFileDownload(file: file, origin: .search)
        )

        await model.performDownloadNoticeAction()

        XCTAssertNil(model.downloadNotice)
        XCTAssertEqual(model.downloads.first?.filename, "9709_s24_qp_12.pdf")
        XCTAssertNil(model.errorMessage)
    }

    func testStartSearchDownloadUsesConfiguredSaveDirectory() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperSearchDownloadConfiguredDirectoryTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let saveDirectory = pathsRoot.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        let manager = DownloadManager(
            sharedTransfer: { _, partialURL, _, _ in
                try Data("ok".utf8).write(to: partialURL)
            },
            sessionStore: DownloadSessionStore(paths: paths)
        )
        let backend = try NativeBackendService(paths: paths, downloadManager: manager)
        let model = AppModel(backend: backend)
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        model.settings.saveDirectory = saveDirectory.path
        model.searchGroups = [model.backendGroup(for: file)]
        model.route = .search

        await model.startSearchDownload()

        XCTAssertEqual(model.route, .downloads)
        XCTAssertEqual(model.downloads.first?.filename, file.filename)
        XCTAssertTrue(model.downloads.first?.savePath.hasPrefix(saveDirectory.path) ?? false)
        XCTAssertNil(model.downloadNotice)
        XCTAssertNil(model.saveDirectoryNotice)
        XCTAssertNil(model.errorMessage)
    }

    func testStartBatchDownloadUsesConfiguredCreatableSaveDirectory() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperBatchDownloadConfiguredDirectoryTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let saveDirectory = pathsRoot.appendingPathComponent("downloads", isDirectory: true)
        let manager = DownloadManager(
            sharedTransfer: { _, partialURL, _, _ in
                try Data("ok".utf8).write(to: partialURL)
            },
            sessionStore: DownloadSessionStore(paths: paths)
        )
        let backend = try NativeBackendService(paths: paths, downloadManager: manager)
        let model = AppModel(backend: backend)
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        model.settings.saveDirectory = saveDirectory.path
        model.batchGroups = [model.backendGroup(for: file)]
        model.route = .batch

        await model.startBatchDownload()

        XCTAssertEqual(model.route, .downloads)
        XCTAssertEqual(model.downloads.first?.filename, file.filename)
        XCTAssertTrue(model.downloads.first?.savePath.hasPrefix(saveDirectory.path) ?? false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: saveDirectory.path))
        XCTAssertNil(model.downloadNotice)
        XCTAssertNil(model.saveDirectoryNotice)
        XCTAssertNil(model.errorMessage)
    }

    func testResolvedSaveDirectoryPersistsChosenDirectoryBeforeReturningIt() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperResolvedSaveDirectoryPersistTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let chosenDirectory = pathsRoot.appendingPathComponent("chosen", isDirectory: true)
        let backend = try NativeBackendService(
            paths: paths,
            directoryChooser: { chosenDirectory.path }
        )
        let model = AppModel(backend: backend)
        await model.loadSettings()
        let originalDirectory = model.settings.saveDirectory
        let invalidFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperResolvedSaveDirectoryInvalid-\(UUID().uuidString).txt", isDirectory: false)
        FileManager.default.createFile(atPath: invalidFileURL.path, contents: Data("blocked".utf8))
        defer { try? FileManager.default.removeItem(at: invalidFileURL) }
        model.settings.saveDirectory = invalidFileURL.path

        let resolvedDirectory = try await model.resolvedSaveDirectory()

        guard case let .ready(resolvedPath) = resolvedDirectory else {
            return XCTFail("Expected ready save-directory resolution")
        }
        XCTAssertEqual(resolvedPath, chosenDirectory.path)
        XCTAssertEqual(model.settings.saveDirectory, chosenDirectory.path)
        XCTAssertEqual(backend.loadSettings().saveDirectory, chosenDirectory.path)
        XCTAssertNotEqual(originalDirectory, model.settings.saveDirectory)
        XCTAssertNil(model.settingsNotice)
    }

    func testResolvedSaveDirectoryReturnsNilWhenChosenDirectoryCannotBeSaved() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperResolvedSaveDirectoryFailureTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let chosenDirectory = pathsRoot.appendingPathComponent("chosen", isDirectory: true)
        let backend = try NativeBackendService(
            paths: paths,
            directoryChooser: { chosenDirectory.path }
        )
        let model = AppModel(backend: backend)
        await model.loadSettings()
        let invalidFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperResolvedSaveDirectoryFailureInvalid-\(UUID().uuidString).txt", isDirectory: false)
        FileManager.default.createFile(atPath: invalidFileURL.path, contents: Data("blocked".utf8))
        defer { try? FileManager.default.removeItem(at: invalidFileURL) }
        model.settings.saveDirectory = invalidFileURL.path

        try FileManager.default.removeItem(at: pathsRoot)
        FileManager.default.createFile(atPath: pathsRoot.path, contents: Data("blocked".utf8))
        defer { try? FileManager.default.removeItem(at: pathsRoot) }

        let resolvedDirectory = try await model.resolvedSaveDirectory()

        guard case let .persistenceFailed(diagnostic) = resolvedDirectory else {
            return XCTFail("Expected persistenceFailed save-directory resolution")
        }
        XCTAssertEqual(diagnostic.message, model.settingsNotice?.message)
        XCTAssertEqual(model.settings.saveDirectory, invalidFileURL.path)
        XCTAssertEqual(model.settingsNotice?.message, model.lastDiagnostic?.message)
        XCTAssertEqual(model.lastDiagnostic?.context, .settings)
        XCTAssertNil(model.errorMessage)
    }

    func testStartSingleFileDownloadDoesNotProceedWhenChosenDirectoryCannotBeSaved() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperSingleFileChosenDirectoryFailureTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let chosenDirectory = pathsRoot.appendingPathComponent("chosen", isDirectory: true)
        let manager = DownloadManager(
            sharedTransfer: { _, partialURL, _, _ in
                try Data("ok".utf8).write(to: partialURL)
            },
            sessionStore: DownloadSessionStore(paths: paths)
        )
        let backend = try NativeBackendService(
            paths: paths,
            downloadManager: manager,
            directoryChooser: { chosenDirectory.path }
        )
        let model = AppModel(backend: backend)
        await model.loadSettings()
        let invalidFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperSingleFileChosenDirectoryFailureInvalid-\(UUID().uuidString).txt", isDirectory: false)
        FileManager.default.createFile(atPath: invalidFileURL.path, contents: Data("blocked".utf8))
        defer { try? FileManager.default.removeItem(at: invalidFileURL) }
        model.settings.saveDirectory = invalidFileURL.path

        try FileManager.default.removeItem(at: pathsRoot)
        FileManager.default.createFile(atPath: pathsRoot.path, contents: Data("blocked".utf8))
        defer { try? FileManager.default.removeItem(at: pathsRoot) }

        await model.startSingleFileDownload(makePaperFile(filename: "9709_s24_qp_12.pdf"))

        XCTAssertTrue(model.downloads.isEmpty)
        XCTAssertEqual(model.downloadNotice?.message, model.settingsNotice?.message)
        guard case let .retrySingleFileDownload(file, origin)? = model.downloadNotice?.action else {
            return XCTFail("Expected retryable single-file download notice")
        }
        XCTAssertEqual(file.filename, "9709_s24_qp_12.pdf")
        XCTAssertEqual(origin, .search)
        XCTAssertEqual(model.settings.saveDirectory, invalidFileURL.path)
        XCTAssertEqual(model.settingsNotice?.message, model.lastDiagnostic?.message)
        XCTAssertEqual(model.lastDiagnostic?.context, .settings)
        XCTAssertNil(model.errorMessage)
    }

    func testStartSearchDownloadShowsRetryableDownloadNoticeWhenChosenDirectoryCannotBeSaved() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperSearchChosenDirectoryFailureTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let chosenDirectory = pathsRoot.appendingPathComponent("chosen", isDirectory: true)
        let manager = DownloadManager(
            sharedTransfer: { _, partialURL, _, _ in
                try Data("ok".utf8).write(to: partialURL)
            },
            sessionStore: DownloadSessionStore(paths: paths)
        )
        let backend = try NativeBackendService(
            paths: paths,
            downloadManager: manager,
            directoryChooser: { chosenDirectory.path }
        )
        let model = AppModel(backend: backend)
        await model.loadSettings()
        let invalidFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperSearchChosenDirectoryFailureInvalid-\(UUID().uuidString).txt", isDirectory: false)
        FileManager.default.createFile(atPath: invalidFileURL.path, contents: Data("blocked".utf8))
        defer { try? FileManager.default.removeItem(at: invalidFileURL) }
        model.settings.saveDirectory = invalidFileURL.path
        model.searchGroups = [model.backendGroup(for: makePaperFile(filename: "9709_s24_qp_12.pdf"))]

        try FileManager.default.removeItem(at: pathsRoot)
        FileManager.default.createFile(atPath: pathsRoot.path, contents: Data("blocked".utf8))
        defer { try? FileManager.default.removeItem(at: pathsRoot) }

        await model.startSearchDownload()

        XCTAssertTrue(model.downloads.isEmpty)
        XCTAssertEqual(model.downloadNotice?.message, model.settingsNotice?.message)
        XCTAssertEqual(model.downloadNotice?.action, .retrySearchDownload)
        XCTAssertEqual(model.lastDiagnostic?.context, .settings)
        XCTAssertNil(model.errorMessage)
    }

    func testLatestDiagnosticForContextPreservesIndependentTracks() throws {
        let model = try makeBasicModel()

        let sourceDiagnostic = model.recordDiagnostic(context: .sourceProvider, message: "FrankCIE: 无结果")
        let previewDiagnostic = model.recordDiagnostic(context: .preview, message: "预览失败")
        let downloadDiagnostic = model.recordDiagnostic(context: .download, message: "下载失败")

        XCTAssertEqual(model.latestDiagnostic(for: .sourceProvider), sourceDiagnostic)
        XCTAssertEqual(model.latestDiagnostic(for: .preview), previewDiagnostic)
        XCTAssertEqual(model.latestDiagnostic(for: .download), downloadDiagnostic)
        XCTAssertEqual(model.lastDiagnostic, downloadDiagnostic)
    }

    func testLatestDiagnosticForContextUpdatesOnlyThatContext() throws {
        let model = try makeBasicModel()

        _ = model.recordDiagnostic(context: .sourceProvider, message: "FrankCIE: 无结果")
        let secondSourceDiagnostic = model.recordDiagnostic(context: .sourceProvider, message: "EasyPaper: 失败")
        let previewDiagnostic = model.recordDiagnostic(context: .preview, message: "预览失败")

        XCTAssertEqual(model.latestDiagnostic(for: .sourceProvider), secondSourceDiagnostic)
        XCTAssertEqual(model.latestDiagnostic(for: .preview), previewDiagnostic)
    }

    func testRecordDownloadFailuresIfNeededDoesNotRewriteSameFailureSet() throws {
        let model = try makeBasicModel()
        let snapshot = DownloadStatusSnapshot(
            phase: .done,
            done: 1,
            total: 2,
            success: 1,
            message: "完成",
            failed: 1,
            cancelled: 0,
            skipped: 0
        )
        let items = [
            DownloadTaskItem(id: 1, filename: "ok.pdf", ftype: "QP", label: "Paper 1", year: "2024", savePath: "/tmp/ok.pdf", status: .done, error: "", errorType: nil),
            DownloadTaskItem(id: 2, filename: "bad.pdf", ftype: "QP", label: "Paper 2", year: "2024", savePath: "/tmp/bad.pdf", status: .failed, error: "network", errorType: .network)
        ]

        model.recordDownloadFailuresIfNeeded(snapshot: snapshot, items: items)
        let firstDiagnostic = try XCTUnwrap(model.latestDiagnostic(for: .download))

        model.recordDownloadFailuresIfNeeded(snapshot: snapshot, items: items)
        let secondDiagnostic = try XCTUnwrap(model.latestDiagnostic(for: .download))

        XCTAssertEqual(secondDiagnostic, firstDiagnostic)
    }

    func testRecordDownloadFailuresIfNeededRewritesWhenFailureSetChanges() throws {
        let model = try makeBasicModel()
        let snapshot = DownloadStatusSnapshot(
            phase: .done,
            done: 1,
            total: 3,
            success: 1,
            message: "完成",
            failed: 1,
            cancelled: 0,
            skipped: 0
        )
        let firstItems = [
            DownloadTaskItem(id: 2, filename: "bad.pdf", ftype: "QP", label: "Paper 2", year: "2024", savePath: "/tmp/bad.pdf", status: .failed, error: "network", errorType: .network)
        ]
        let secondItems = [
            DownloadTaskItem(id: 2, filename: "bad.pdf", ftype: "QP", label: "Paper 2", year: "2024", savePath: "/tmp/bad.pdf", status: .failed, error: "network", errorType: .network),
            DownloadTaskItem(id: 3, filename: "also-bad.pdf", ftype: "MS", label: "Paper 3", year: "2024", savePath: "/tmp/also-bad.pdf", status: .failed, error: "rate limited", errorType: .rateLimit)
        ]

        model.recordDownloadFailuresIfNeeded(snapshot: snapshot, items: firstItems)
        model.recordDownloadFailuresIfNeeded(snapshot: snapshot, items: secondItems)

        XCTAssertEqual(model.latestDiagnostic(for: .download)?.message, "2 个下载任务失败")
        XCTAssertEqual(model.latestDiagnostic(for: .download)?.details.count, 8)
    }

    func testRecordDownloadFailuresIfNeededStoresTypedReasonAndRawErrorSeparately() throws {
        let model = try makeBasicModel()
        let snapshot = DownloadStatusSnapshot(
            phase: .done,
            done: 1,
            total: 1,
            success: 0,
            message: "完成",
            failed: 1,
            cancelled: 0,
            skipped: 0
        )
        let items = [
            DownloadTaskItem(
                id: 2,
                filename: "bad.pdf",
                ftype: "QP",
                label: "Paper 2",
                year: "2024",
                savePath: "/tmp/bad.pdf",
                status: .failed,
                error: "服务器触发限流（HTTP 429），请在 30 秒后重试。",
                errorType: .rateLimit
            )
        ]

        model.recordDownloadFailuresIfNeeded(snapshot: snapshot, items: items)

        let diagnostic = try XCTUnwrap(model.latestDiagnostic(for: .download))
        XCTAssertEqual(
            diagnostic.details,
            [
                SupportDiagnosticDetail(label: "bad.pdf Reason", value: "服务器限流，请稍后重试"),
                SupportDiagnosticDetail(label: "bad.pdf Suggested Action", value: "稍后再试"),
                SupportDiagnosticDetail(label: "bad.pdf Raw Error", value: "服务器触发限流（HTTP 429），请在 30 秒后重试。"),
                SupportDiagnosticDetail(label: "bad.pdf Save Path", value: "/tmp/bad.pdf")
            ]
        )
    }

    func testRefreshDownloadsRecordsRecoveredInterruptedSessionDetails() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRecoveredDownloadModelTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let sessionStore = DownloadSessionStore(paths: paths)
        let saveURL = pathsRoot
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent("recovered.pdf", isDirectory: false)
        try FileManager.default.createDirectory(
            at: saveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let partialURL = saveURL.deletingLastPathComponent()
            .appendingPathComponent("recovered.pdf.part.stale", isDirectory: false)
        try Data("partial".utf8).write(to: partialURL)

        let task = DownloadDestinationTask(
            id: 0,
            component: makeDownloadComponent(filename: "recovered.pdf", type: "QP", sy: "s24"),
            filename: "recovered.pdf",
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
                        filename: "recovered.pdf",
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
                proxyURL: ""
            )
        )

        let backend = try NativeBackendService(paths: paths)
        let model = AppModel(backend: backend)

        await model.refreshDownloads()

        let diagnostic = try XCTUnwrap(model.latestDiagnostic(for: .download))
        let notice = try XCTUnwrap(model.downloadRecoveryNotice)
        XCTAssertEqual(diagnostic.message, "检测到 1 个上次中断的下载任务")
        XCTAssertEqual(
            diagnostic.details,
            [
                SupportDiagnosticDetail(label: "Recovered Failed Tasks", value: "1"),
                SupportDiagnosticDetail(label: "Cleaned Partial Files", value: "1"),
                SupportDiagnosticDetail(label: "recovered.pdf Reason", value: "上次下载在应用退出前中断，请重试"),
                SupportDiagnosticDetail(label: "recovered.pdf Suggested Action", value: "检查网络后重试"),
                SupportDiagnosticDetail(label: "recovered.pdf Save Path", value: saveURL.path)
            ]
        )
        XCTAssertEqual(
            notice.message,
            "检测到 1 个上次中断的任务，已清理 1 个残留临时文件。可直接重试失败项。"
        )
        XCTAssertEqual(notice.diagnostic, diagnostic)
        XCTAssertEqual(model.downloadRecoveredCleanedPartialCount, 1)
        XCTAssertEqual(model.interruptedFailedDownloadCount, 1)
        XCTAssertEqual(
            model.downloadRecoverySummary,
            "当前队列包含 1 个从上次会话恢复的失败任务，启动时已清理 1 个残留临时文件。"
        )
        XCTAssertEqual(model.downloadSnapshot.message, "上次下载在退出时中断，可重试失败项")
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
    }

    func testRetryRecoverableDownloadsClearsRecoveryNoticeWhenQueueRestarts() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRetryRecoveredDownloadModelTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let sessionStore = DownloadSessionStore(paths: paths)
        let saveURL = pathsRoot
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent("recovered.pdf", isDirectory: false)
        try FileManager.default.createDirectory(
            at: saveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let task = DownloadDestinationTask(
            id: 0,
            component: makeDownloadComponent(filename: "recovered.pdf", type: "QP", sy: "s24"),
            filename: "recovered.pdf",
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
                        filename: "recovered.pdf",
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
                proxyURL: ""
            )
        )

        let manager = DownloadManager(
            sharedTransfer: { _, partialURL, _, _ in
                try Data("restored".utf8).write(to: partialURL)
            },
            sessionStore: sessionStore
        )
        let backend = try NativeBackendService(paths: paths, downloadManager: manager)
        let model = AppModel(backend: backend)

        await model.refreshDownloads()
        XCTAssertNotNil(model.downloadRecoveryNotice)
        XCTAssertNotNil(model.downloadRecoverySummary)

        await model.retryRecoverableDownloads()
        XCTAssertNil(model.downloadRecoveryNotice)
        XCTAssertNil(model.downloadRecoverySummary)

        var snapshot = await manager.status()
        for _ in 0..<200 where snapshot.isRunning {
            try await Task.sleep(nanoseconds: 25_000_000)
            snapshot = await manager.status()
        }
        XCTAssertEqual(snapshot.success, 1)

        await model.refreshDownloads()
        XCTAssertNil(model.downloadRecoveryNotice)
    }

    func testRefreshDownloadsShowsIntegrityNoticeWhenCompletedDownloadFileIsMissing() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperMissingCompletedDownloadTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let saveDirectory = pathsRoot.appendingPathComponent("downloads", isDirectory: true)
        let manager = DownloadManager(sharedTransfer: { _, partialURL, _, _ in
            try Data("done".utf8).write(to: partialURL)
        })
        let backend = try NativeBackendService(paths: paths, downloadManager: manager)
        let model = AppModel(backend: backend)
        let filename = "missing-after-download.pdf"
        let savedFileURL = saveDirectory
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent(filename)

        try await manager.start(
            groups: [
                NativePaperGroup(
                    sourceID: .frankcie,
                    subjectCode: "9709",
                    sy: "s24",
                    number: "12",
                    paperGroup: 1,
                    qp: makeDownloadComponent(filename: filename, type: "QP", sy: "s24"),
                    ms: nil,
                    extras: []
                )
            ],
            saveDirectory: saveDirectory,
            options: makeDownloadOptions(threads: 1)
        )
        var snapshot = await manager.status()
        for _ in 0..<200 where snapshot.isRunning {
            try await Task.sleep(nanoseconds: 25_000_000)
            snapshot = await manager.status()
        }
        XCTAssertEqual(snapshot.success, 1)
        try FileManager.default.removeItem(at: savedFileURL)

        await model.refreshDownloads()

        let diagnostic = try XCTUnwrap(model.latestDiagnostic(for: .downloadIntegrity))
        let notice = try XCTUnwrap(model.downloadIntegrityNotice)
        XCTAssertEqual(diagnostic.message, "部分已完成的下载文件已丢失，请重新下载缺失文件。")
        XCTAssertEqual(
            diagnostic.details,
            [
                SupportDiagnosticDetail(label: "\(filename) Status", value: "完成"),
                SupportDiagnosticDetail(label: "\(filename) Save Path", value: savedFileURL.path),
                SupportDiagnosticDetail(label: "\(filename) Integrity", value: "文件不存在。")
            ]
        )
        XCTAssertEqual(notice.message, "发现 1 个已完成的下载文件已丢失。下载记录仍保留，但对应文件需要重新下载。")
        XCTAssertEqual(notice.diagnostic, diagnostic)
        XCTAssertEqual(notice.retryableTaskIDs, [0])
        XCTAssertEqual(model.downloadIntegrityState(for: 0), .missingFile)
        XCTAssertNil(model.errorMessage)
    }

    func testRefreshDownloadsShowsIntegrityNoticeWhenCompletedDownloadFileBecomesEmpty() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperInvalidCompletedDownloadTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let saveDirectory = pathsRoot.appendingPathComponent("downloads", isDirectory: true)
        let manager = DownloadManager(sharedTransfer: { _, partialURL, _, _ in
            try Data("done".utf8).write(to: partialURL)
        })
        let backend = try NativeBackendService(paths: paths, downloadManager: manager)
        let model = AppModel(backend: backend)
        let filename = "empty-after-download.pdf"
        let savedFileURL = saveDirectory
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent(filename)

        try await manager.start(
            groups: [
                NativePaperGroup(
                    sourceID: .frankcie,
                    subjectCode: "9709",
                    sy: "s24",
                    number: "12",
                    paperGroup: 1,
                    qp: makeDownloadComponent(filename: filename, type: "QP", sy: "s24"),
                    ms: nil,
                    extras: []
                )
            ],
            saveDirectory: saveDirectory,
            options: makeDownloadOptions(threads: 1)
        )
        var snapshot = await manager.status()
        for _ in 0..<200 where snapshot.isRunning {
            try await Task.sleep(nanoseconds: 25_000_000)
            snapshot = await manager.status()
        }
        XCTAssertEqual(snapshot.success, 1)
        try Data().write(to: savedFileURL, options: .atomic)

        await model.refreshDownloads()

        let diagnostic = try XCTUnwrap(model.latestDiagnostic(for: .downloadIntegrity))
        let notice = try XCTUnwrap(model.downloadIntegrityNotice)
        XCTAssertEqual(diagnostic.message, "部分已完成的下载文件已不可用，请重新下载或检查对应文件。")
        XCTAssertEqual(
            diagnostic.details,
            [
                SupportDiagnosticDetail(label: "\(filename) Status", value: "完成"),
                SupportDiagnosticDetail(label: "\(filename) Save Path", value: savedFileURL.path),
                SupportDiagnosticDetail(label: "\(filename) Integrity", value: "下载文件为空。")
            ]
        )
        XCTAssertEqual(notice.message, "发现 1 个已完成的下载文件已不可用。下载记录仍保留，但对应文件需要重新下载或检查。")
        XCTAssertEqual(notice.missingFileCount, 0)
        XCTAssertEqual(notice.invalidFileCount, 1)
        XCTAssertEqual(notice.diagnostic, diagnostic)
        XCTAssertEqual(notice.retryableTaskIDs, [0])
        XCTAssertEqual(model.downloadIntegrityState(for: 0), .emptyFile)
        XCTAssertNil(model.errorMessage)
    }

    func testRefreshDownloadsDoesNotOfferRepairRetryWhenCompletedDownloadPathBecomesDirectory() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperDirectoryCompletedDownloadTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let saveDirectory = pathsRoot.appendingPathComponent("downloads", isDirectory: true)
        let manager = DownloadManager(sharedTransfer: { _, partialURL, _, _ in
            try Data("done".utf8).write(to: partialURL)
        })
        let backend = try NativeBackendService(paths: paths, downloadManager: manager)
        let model = AppModel(backend: backend)
        let filename = "directory-after-download.pdf"
        let savedFileURL = saveDirectory
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent(filename)

        try await manager.start(
            groups: [
                NativePaperGroup(
                    sourceID: .frankcie,
                    subjectCode: "9709",
                    sy: "s24",
                    number: "12",
                    paperGroup: 1,
                    qp: makeDownloadComponent(filename: filename, type: "QP", sy: "s24"),
                    ms: nil,
                    extras: []
                )
            ],
            saveDirectory: saveDirectory,
            options: makeDownloadOptions(threads: 1)
        )
        var snapshot = await manager.status()
        for _ in 0..<200 where snapshot.isRunning {
            try await Task.sleep(nanoseconds: 25_000_000)
            snapshot = await manager.status()
        }
        try FileManager.default.removeItem(at: savedFileURL)
        try FileManager.default.createDirectory(at: savedFileURL, withIntermediateDirectories: true)

        await model.refreshDownloads()

        let notice = try XCTUnwrap(model.downloadIntegrityNotice)
        XCTAssertEqual(notice.invalidFileCount, 1)
        XCTAssertEqual(notice.retryableTaskIDs, [])
        XCTAssertEqual(model.downloadIntegrityState(for: 0), .directoryPath)
    }

    func testRetryDownloadsNeedingRepairRestartsQueueForMissingCompletedFile() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRetryRepairCompletedDownloadTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let saveDirectory = pathsRoot.appendingPathComponent("downloads", isDirectory: true)
        let attempts = AttemptCounter()
        let manager = DownloadManager(sharedTransfer: { _, partialURL, _, _ in
            let current = await attempts.next()
            try Data("attempt-\(current)".utf8).write(to: partialURL)
        })
        let backend = try NativeBackendService(paths: paths, downloadManager: manager)
        let model = AppModel(backend: backend)
        let filename = "missing-then-retried.pdf"
        let savedFileURL = saveDirectory
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent(filename)

        try await manager.start(
            groups: [
                NativePaperGroup(
                    sourceID: .frankcie,
                    subjectCode: "9709",
                    sy: "s24",
                    number: "12",
                    paperGroup: 1,
                    qp: makeDownloadComponent(filename: filename, type: "QP", sy: "s24"),
                    ms: nil,
                    extras: []
                )
            ],
            saveDirectory: saveDirectory,
            options: makeDownloadOptions(threads: 1)
        )
        var snapshot = await manager.status()
        for _ in 0..<200 where snapshot.isRunning {
            try await Task.sleep(nanoseconds: 25_000_000)
            snapshot = await manager.status()
        }
        try FileManager.default.removeItem(at: savedFileURL)

        await model.refreshDownloads()
        XCTAssertEqual(model.downloadIntegrityNotice?.retryableTaskIDs, [0])
        XCTAssertEqual(model.downloadIntegrityState(for: 0), .missingFile)

        await model.retryDownloadsNeedingRepair()

        snapshot = await manager.status()
        for _ in 0..<200 where snapshot.isRunning {
            try await Task.sleep(nanoseconds: 25_000_000)
            snapshot = await manager.status()
        }
        XCTAssertEqual(snapshot.success, 1)
        XCTAssertEqual(try String(contentsOf: savedFileURL), "attempt-2")

        await model.refreshDownloads()
        XCTAssertNil(model.downloadIntegrityNotice)
        XCTAssertTrue(model.downloadIntegrityStatesByTaskID.isEmpty)
    }

    func testRefreshDownloadsClearsIntegrityNoticeAfterCompletedFileReturns() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRestoreCompletedDownloadTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let saveDirectory = pathsRoot.appendingPathComponent("downloads", isDirectory: true)
        let manager = DownloadManager(sharedTransfer: { _, partialURL, _, _ in
            try Data("done".utf8).write(to: partialURL)
        })
        let backend = try NativeBackendService(paths: paths, downloadManager: manager)
        let model = AppModel(backend: backend)
        let filename = "restored-download.pdf"
        let savedFileURL = saveDirectory
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent(filename)

        try await manager.start(
            groups: [
                NativePaperGroup(
                    sourceID: .frankcie,
                    subjectCode: "9709",
                    sy: "s24",
                    number: "12",
                    paperGroup: 1,
                    qp: makeDownloadComponent(filename: filename, type: "QP", sy: "s24"),
                    ms: nil,
                    extras: []
                )
            ],
            saveDirectory: saveDirectory,
            options: makeDownloadOptions(threads: 1)
        )
        var snapshot = await manager.status()
        for _ in 0..<200 where snapshot.isRunning {
            try await Task.sleep(nanoseconds: 25_000_000)
            snapshot = await manager.status()
        }
        try FileManager.default.removeItem(at: savedFileURL)

        await model.refreshDownloads()
        XCTAssertNotNil(model.downloadIntegrityNotice)
        XCTAssertEqual(model.downloadIntegrityState(for: 0), .missingFile)

        try Data("restored".utf8).write(to: savedFileURL)
        await model.refreshDownloads()

        XCTAssertNil(model.downloadIntegrityNotice)
        XCTAssertTrue(model.downloadIntegrityStatesByTaskID.isEmpty)
    }

    func testRefreshDownloadsClearsIntegrityNoticeAfterCompletedFileBecomesUsableAgain() async throws {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRepairCompletedDownloadTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let saveDirectory = pathsRoot.appendingPathComponent("downloads", isDirectory: true)
        let manager = DownloadManager(sharedTransfer: { _, partialURL, _, _ in
            try Data("done".utf8).write(to: partialURL)
        })
        let backend = try NativeBackendService(paths: paths, downloadManager: manager)
        let model = AppModel(backend: backend)
        let filename = "repairable-download.pdf"
        let savedFileURL = saveDirectory
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent(filename)

        try await manager.start(
            groups: [
                NativePaperGroup(
                    sourceID: .frankcie,
                    subjectCode: "9709",
                    sy: "s24",
                    number: "12",
                    paperGroup: 1,
                    qp: makeDownloadComponent(filename: filename, type: "QP", sy: "s24"),
                    ms: nil,
                    extras: []
                )
            ],
            saveDirectory: saveDirectory,
            options: makeDownloadOptions(threads: 1)
        )
        var snapshot = await manager.status()
        for _ in 0..<200 where snapshot.isRunning {
            try await Task.sleep(nanoseconds: 25_000_000)
            snapshot = await manager.status()
        }

        try Data().write(to: savedFileURL, options: .atomic)
        await model.refreshDownloads()
        XCTAssertNotNil(model.downloadIntegrityNotice)
        XCTAssertEqual(model.downloadIntegrityState(for: 0), .emptyFile)

        try Data("restored".utf8).write(to: savedFileURL, options: .atomic)
        await model.refreshDownloads()

        XCTAssertNil(model.downloadIntegrityNotice)
        XCTAssertTrue(model.downloadIntegrityStatesByTaskID.isEmpty)
    }

    func testStartupUpdateCheckRunsOnlyOnceAndDoesNotPromptWhenUpToDate() async throws {
        let counter = UpdateCallCounter()
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.3"),
            counter: counter
        )

        await model.checkForUpdates(source: .startup)
        await model.checkForUpdates(source: .startup)

        let callCount = await counter.value()
        XCTAssertEqual(callCount, 1)
        XCTAssertNil(model.pendingUpdatePrompt)
        XCTAssertEqual(model.updateStatus, .upToDate(current: "6.0.3", latest: "6.0.3"))
    }

    func testManualUpdateCheckFailureUsesContextualNoticeInsteadOfGlobalError() async throws {
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Data("{}".utf8)
        )

        await model.checkForUpdates(source: .manual)

        guard case let .failed(failure) = model.updateStatus else {
            return XCTFail("Expected failed update status")
        }
        XCTAssertEqual(failure.phase, .check)
        XCTAssertEqual(failure.message, model.updateNotice?.message)
        XCTAssertNil(failure.release)
        XCTAssertEqual(model.updateNotice?.action, .retryCheck)
        XCTAssertEqual(model.lastDiagnostic?.context, .update)
        XCTAssertNil(model.errorMessage)
    }

    func testUpdateNoticeRevealActionTitleUsesDownloadedFileWhenUpdateArtifactIsAccessible() throws {
        let model = try makeBasicModel()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperUpdateNoticeReveal-\(UUID().uuidString).dmg", isDirectory: false)
        try Data("update".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        model.updateStatus = .downloaded(
            DownloadedUpdateState(
                release: AppUpdateRelease(
                    version: "6.0.4",
                    tagName: "v6.0.4",
                    name: "C-Paper 6.0.4",
                    htmlURL: URL(string: "https://example.test/release")!,
                    assetName: "C-Paper.dmg",
                    downloadURL: URL(string: "https://example.test/C-Paper.dmg")!
                ),
                fileURL: fileURL,
                installState: .requiresManualOpen
            )
        )

        XCTAssertEqual(model.updateNoticeRevealActionTitle, "显示文件")
    }

    func testUpdateNoticeRevealActionTitleFallsBackToSupportFolderWhenUpdateArtifactIsUnavailable() throws {
        let model = try makeBasicModel()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperUpdateNoticeMissing-\(UUID().uuidString).dmg", isDirectory: false)
        model.updateStatus = .downloaded(
            DownloadedUpdateState(
                release: AppUpdateRelease(
                    version: "6.0.4",
                    tagName: "v6.0.4",
                    name: "C-Paper 6.0.4",
                    htmlURL: URL(string: "https://example.test/release")!,
                    assetName: "C-Paper.dmg",
                    downloadURL: URL(string: "https://example.test/C-Paper.dmg")!
                ),
                fileURL: fileURL,
                installState: .missingFile
            )
        )

        XCTAssertEqual(model.updateNoticeRevealActionTitle, "显示支持文件夹")
    }

    func testStartupUpdateCheckPromptsWhenNewVersionExistsWithoutDownloading() async throws {
        let counter = UpdateCallCounter()
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            counter: counter
        )

        await model.checkForUpdates(source: .startup)

        let callCount = await counter.value()
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(model.pendingUpdatePrompt?.version, "6.0.4")
        XCTAssertEqual(model.updateStatus.availableRelease?.version, "6.0.4")
    }

    func testStartupUpdateCheckRestoresPreviouslyDownloadedArtifactForLatestRelease() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelStartupRestoredUpdateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let downloadedURL = tempDirectory.appendingPathComponent("C-Paper-Native-6.0.4-standalone-20260604.dmg")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try Data("update".utf8).write(to: downloadedURL)
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory
        )

        await model.checkForUpdates(source: .startup)

        XCTAssertEqual(model.pendingUpdatePrompt?.version, "6.0.4")
        guard case let .downloaded(state) = model.updateStatus else {
            return XCTFail("Expected startup update check to restore downloaded update state")
        }
        XCTAssertEqual(state.fileURL, downloadedURL)
        XCTAssertEqual(state.installState, .requiresManualOpen)
        XCTAssertEqual(state.origin, .restoredArtifact)
        XCTAssertEqual(model.updateStatus.message, "已恢复本地更新 DMG，等待手动打开")
        XCTAssertEqual(
            model.updateDownloadedSummary,
            "当前更新包来自之前已下载的本地 DMG，不是本次会话刚下载的文件，可直接手动打开安装。"
        )
        XCTAssertTrue(model.updateStatus.canAccessDownloadedFile)
        XCTAssertNil(model.updateNotice)
    }

    func testManualUpdateCheckRestoresPreviouslyDownloadedArtifactWithoutStartupPrompt() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelManualRestoredUpdateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let downloadedURL = tempDirectory.appendingPathComponent("C-Paper-Native-6.0.4-standalone-20260604.dmg")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try Data("update".utf8).write(to: downloadedURL)
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory
        )

        await model.checkForUpdates(source: .manual)

        XCTAssertNil(model.pendingUpdatePrompt)
        guard case let .downloaded(state) = model.updateStatus else {
            return XCTFail("Expected manual update check to restore downloaded update state")
        }
        XCTAssertEqual(state.fileURL, downloadedURL)
        XCTAssertEqual(state.installState, .requiresManualOpen)
        XCTAssertEqual(state.origin, .restoredArtifact)
        XCTAssertTrue(model.updateStatus.canAccessDownloadedFile)
    }

    func testUpdateCheckDoesNotRestoreEmptyDownloadedArtifact() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelInvalidRestoredUpdateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let downloadedURL = tempDirectory.appendingPathComponent("C-Paper-Native-6.0.4-standalone-20260604.dmg")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try Data().write(to: downloadedURL)
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory
        )

        await model.checkForUpdates(source: .manual)

        XCTAssertEqual(model.updateStatus.availableRelease?.version, "6.0.4")
        XCTAssertFalse(model.updateStatus.canAccessDownloadedFile)
    }

    func testDownloadAvailableUpdateClearsPromptAndStoresDownloadedURL() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory
        )
        await model.checkForUpdates(source: .startup)

        await model.downloadAvailableUpdate()

        XCTAssertNil(model.pendingUpdatePrompt)
        guard let downloadedURL = model.updateStatus.downloadedURL else {
            return XCTFail("Expected downloaded update URL")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloadedURL.path))
        XCTAssertEqual(try String(contentsOf: downloadedURL), "update")
    }

    func testDownloadAvailableUpdateStatusPreservesDestinationURLWhileDownloading() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateProgressTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let coordinator = UpdateDownloadCoordinator()
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory,
            downloadWriter: { _, destinationURL, _, progress in
                await progress(0.5)
                await coordinator.recordProgress()
                await coordinator.waitForFinishPermission()
                try Data("update".utf8).write(to: destinationURL)
            }
        )
        await model.checkForUpdates(source: .startup)

        let downloadTask = Task {
            await model.downloadAvailableUpdate()
        }
        await coordinator.waitForProgress()

        guard case let .downloading(state) = model.updateStatus else {
            await coordinator.allowFinish()
            await downloadTask.value
            return XCTFail("Expected update status to stay downloading while transfer is in flight.")
        }
        XCTAssertEqual(state.progress, 0.5)
        XCTAssertEqual(state.release.version, "6.0.4")
        XCTAssertEqual(state.destinationURL, tempDirectory.appendingPathComponent("C-Paper-Native-6.0.4-standalone-20260604.dmg"))

        await coordinator.allowFinish()
        await downloadTask.value
    }

    func testDownloadAvailableUpdateAutomaticallyOpensDownloadedDMG() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateOpenTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let recorder = URLRecorder()
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory,
            openDownloadedFile: { url in
                recorder.record(url)
                return true
            }
        )
        await model.checkForUpdates(source: .startup)
        await model.downloadAvailableUpdate()

        let downloadedURL = try XCTUnwrap(model.updateStatus.downloadedURL)
        XCTAssertEqual(recorder.values(), [downloadedURL])
        guard case let .downloaded(state) = model.updateStatus else {
            return XCTFail("Expected downloaded update state after successful download")
        }
        XCTAssertEqual(state.origin, .currentSession)
        XCTAssertEqual(
            model.updateDownloadedSummary,
            "当前更新包已在本次会话下载完成。"
        )
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.updateNotice)
    }

    func testOpenDownloadedUpdateFileUsesInjectedOpenDownloadedFileClosure() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelManualUpdateOpenTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let recorder = URLRecorder()
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory,
            openDownloadedFile: { url in
                recorder.record(url)
                return true
            }
        )
        await model.checkForUpdates(source: .startup)
        await model.downloadAvailableUpdate()

        let didOpen = model.openDownloadedUpdateFile()

        XCTAssertTrue(didOpen)
        let openedURL = recorder.lastValue()
        XCTAssertEqual(openedURL, model.updateStatus.downloadedURL)
        XCTAssertEqual(openedURL?.pathExtension, "dmg")
        XCTAssertEqual(recorder.values().count, 2)
    }

    func testDownloadAvailableUpdateOpenFailureKeepsDownloadedURLAndShowsGuidance() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateOpenFailureTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory,
            openDownloadedFile: { _ in false }
        )
        await model.checkForUpdates(source: .startup)
        await model.downloadAvailableUpdate()
        let downloadedURL = try XCTUnwrap(model.updateStatus.downloadedURL)

        guard case let .downloaded(downloadedState) = model.updateStatus else {
            return XCTFail("Expected downloaded update state")
        }
        XCTAssertEqual(model.updateNotice?.message, "更新 DMG 已下载，但打开失败，请在设置中重试或手动检查文件。")
        XCTAssertEqual(model.updateNotice?.action, .openDownloadedDMG)
        XCTAssertEqual(downloadedState.installState, .requiresManualOpen)
        XCTAssertEqual(downloadedState.origin, .currentSession)
        XCTAssertEqual(model.lastDiagnostic?.context, .update)
        XCTAssertEqual(model.lastDiagnostic?.message, model.updateNotice?.message)
        XCTAssertTrue(model.lastDiagnostic?.details.contains(where: { $0.label == "Downloaded File" }) == true)
        XCTAssertNil(model.errorMessage)

        let didOpen = model.openDownloadedUpdate()

        XCTAssertFalse(didOpen)
        XCTAssertEqual(model.updateStatus.downloadedURL, downloadedURL)
        XCTAssertEqual(model.updateNotice?.message, "更新 DMG 已下载，但打开失败，请在设置中重试或手动检查文件。")
    }

    func testDownloadAvailableUpdateFailureKeepsRetryTargetInTypedFailedState() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateRetryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory,
            downloadWriter: { _, _, _, _ in
                throw URLError(.networkConnectionLost)
            }
        )
        await model.checkForUpdates(source: .startup)

        await model.downloadAvailableUpdate()

        guard case let .failed(failure) = model.updateStatus else {
            return XCTFail("Expected typed failed update status")
        }
        XCTAssertEqual(failure.phase, .download)
        XCTAssertEqual(failure.release?.version, "6.0.4")
        XCTAssertEqual(failure.destinationURL, tempDirectory.appendingPathComponent("C-Paper-Native-6.0.4-standalone-20260604.dmg"))
        XCTAssertEqual(model.updateStatus.availableRelease?.version, "6.0.4")
        XCTAssertEqual(model.updateNotice?.message, model.lastDiagnostic?.message)
        XCTAssertEqual(model.updateNotice?.action, .retryDownload)
        XCTAssertNil(model.pendingUpdatePrompt)
        XCTAssertNil(model.errorMessage)
    }

    func testPerformUpdateNoticeActionClearsOpenFailureNoticeAfterManualSuccess() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateManualSuccessTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let shouldSucceed = MutableBoolBox(false)
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory,
            openDownloadedFile: { _ in
                shouldSucceed.value
            }
        )
        await model.checkForUpdates(source: .startup)
        await model.downloadAvailableUpdate()

        XCTAssertNotNil(model.updateNotice)
        XCTAssertEqual(model.updateNotice?.action, .openDownloadedDMG)
        shouldSucceed.value = true

        await model.performUpdateNoticeAction()

        XCTAssertNil(model.updateNotice)
        guard case let .downloaded(state) = model.updateStatus else {
            return XCTFail("Expected downloaded update state after manual open")
        }
        XCTAssertEqual(state.installState, .downloaded)
    }

    func testOpenDownloadedUpdateFailureAfterSuccessfulDownloadCreatesContextualNotice() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateManualOpenFailureTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let shouldSucceed = MutableBoolBox(true)
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory,
            openDownloadedFile: { _ in
                shouldSucceed.value
            }
        )
        await model.checkForUpdates(source: .startup)
        await model.downloadAvailableUpdate()

        XCTAssertNil(model.updateNotice)
        shouldSucceed.value = false

        let didOpen = model.openDownloadedUpdate()

        XCTAssertFalse(didOpen)
        XCTAssertEqual(model.updateNotice?.message, "更新 DMG 已下载，但打开失败，请在设置中重试或手动检查文件。")
        XCTAssertEqual(model.updateNotice?.action, .openDownloadedDMG)
        guard case let .downloaded(state) = model.updateStatus else {
            return XCTFail("Expected downloaded update state after failed manual open")
        }
        XCTAssertEqual(state.installState, .requiresManualOpen)
        XCTAssertEqual(model.lastDiagnostic?.context, .update)
        XCTAssertNil(model.errorMessage)
    }

    func testDownloadAvailableUpdateWithInvalidDownloadedFileRequestsRedownloadWithoutOpenAttempt() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateInvalidFileTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let recorder = URLRecorder()
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory,
            openDownloadedFile: { url in
                recorder.record(url)
                return true
            },
            downloadWriter: { _, destinationURL, _, _ in
                try Data().write(to: destinationURL)
            }
        )
        await model.checkForUpdates(source: .startup)

        await model.downloadAvailableUpdate()

        XCTAssertTrue(recorder.values().isEmpty)
        XCTAssertEqual(model.updateNotice?.message, "已下载的更新 DMG 无法使用，请重新下载。")
        XCTAssertEqual(model.updateNotice?.action, .retryDownload)
        guard case let .downloaded(state) = model.updateStatus else {
            return XCTFail("Expected downloaded update state after invalid file detection")
        }
        XCTAssertEqual(state.installState, .invalidFile)
        XCTAssertFalse(model.updateStatus.canAccessDownloadedFile)
        XCTAssertEqual(model.lastDiagnostic?.context, .update)
        XCTAssertTrue(model.lastDiagnostic?.details.contains(where: { $0.label == "Reason" && $0.value == "更新文件为空。" }) == true)
        XCTAssertNil(model.errorMessage)
    }

    func testOpenDownloadedUpdateWhenDownloadedFileIsMissingRequestsRedownload() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateMissingFileOpenTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let recorder = URLRecorder()
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory,
            openDownloadedFile: { url in
                recorder.record(url)
                return true
            }
        )
        await model.checkForUpdates(source: .startup)
        await model.downloadAvailableUpdate()
        let downloadedURL = try XCTUnwrap(model.updateStatus.downloadedURL)
        try FileManager.default.removeItem(at: downloadedURL)

        let didOpen = model.openDownloadedUpdate()

        XCTAssertFalse(didOpen)
        XCTAssertEqual(recorder.values(), [downloadedURL])
        XCTAssertEqual(model.updateNotice?.message, "已下载的更新 DMG 不存在，请重新下载。")
        XCTAssertEqual(model.updateNotice?.action, .retryDownload)
        guard case let .downloaded(state) = model.updateStatus else {
            return XCTFail("Expected downloaded update state after missing file detection")
        }
        XCTAssertEqual(state.installState, .missingFile)
        XCTAssertFalse(model.updateStatus.canAccessDownloadedFile)
        XCTAssertEqual(model.lastDiagnostic?.context, .update)
        XCTAssertNil(model.errorMessage)
    }

    func testRevealDownloadedUpdateWhenDownloadedFileBecomesDirectoryRequestsRedownload() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateInvalidRevealTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory
        )
        await model.checkForUpdates(source: .startup)
        await model.downloadAvailableUpdate()
        let downloadedURL = try XCTUnwrap(model.updateStatus.downloadedURL)
        try FileManager.default.removeItem(at: downloadedURL)
        try FileManager.default.createDirectory(at: downloadedURL, withIntermediateDirectories: true)

        model.revealDownloadedUpdate()

        XCTAssertEqual(model.updateNotice?.message, "已下载的更新 DMG 无法使用，请重新下载。")
        XCTAssertEqual(model.updateNotice?.action, .retryDownload)
        guard case let .downloaded(state) = model.updateStatus else {
            return XCTFail("Expected downloaded update state after invalid file detection")
        }
        XCTAssertEqual(state.installState, .invalidFile)
        XCTAssertFalse(model.updateStatus.canAccessDownloadedFile)
        XCTAssertEqual(model.lastDiagnostic?.context, .update)
        XCTAssertTrue(model.lastDiagnostic?.details.contains(where: { $0.label == "Reason" && $0.value == "更新路径指向目录而不是 DMG 文件。" }) == true)
        XCTAssertNil(model.errorMessage)
    }

    func testRevealDownloadedUpdateWhenDownloadedFileIsMissingRequestsRedownload() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateMissingFileRevealTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory
        )
        await model.checkForUpdates(source: .startup)
        await model.downloadAvailableUpdate()
        let downloadedURL = try XCTUnwrap(model.updateStatus.downloadedURL)
        try FileManager.default.removeItem(at: downloadedURL)

        model.revealDownloadedUpdate()

        XCTAssertEqual(model.updateNotice?.message, "已下载的更新 DMG 不存在，请重新下载。")
        XCTAssertEqual(model.updateNotice?.action, .retryDownload)
        guard case let .downloaded(state) = model.updateStatus else {
            return XCTFail("Expected downloaded update state after missing file detection")
        }
        XCTAssertEqual(state.installState, .missingFile)
        XCTAssertFalse(model.updateStatus.canAccessDownloadedFile)
        XCTAssertEqual(model.lastDiagnostic?.context, .update)
        XCTAssertNil(model.errorMessage)
    }

    func testPerformUpdateNoticeActionRetriesFailedUpdateDownload() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateRetryActionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let shouldSucceed = MutableBoolBox(false)
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory,
            downloadWriter: { _, destinationURL, _, _ in
                guard shouldSucceed.value else {
                    throw URLError(.networkConnectionLost)
                }
                try Data("update".utf8).write(to: destinationURL)
            }
        )
        await model.checkForUpdates(source: .startup)
        await model.downloadAvailableUpdate()

        XCTAssertEqual(model.updateNotice?.action, .retryDownload)
        shouldSucceed.value = true

        await model.performUpdateNoticeAction()

        XCTAssertNil(model.updateNotice)
        XCTAssertNotNil(model.updateStatus.downloadedURL)
    }

    private func makeModel(
        currentVersion: String,
        releaseJSON: Data,
        updatesDirectory: URL? = nil,
        counter: UpdateCallCounter = UpdateCallCounter(),
        openDownloadedFile: @escaping (URL) -> Bool = { _ in true },
        downloadWriter: UpdateService.DownloadWriter? = nil
    ) throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let updateService = UpdateService(
            currentVersion: currentVersion,
            updatesDirectory: updatesDirectory,
            networkClientFactory: { _ in
                CountedUpdateNetworkClient(data: releaseJSON, counter: counter)
            },
            downloadWriter: downloadWriter ?? { _, destinationURL, _, progress in
                await progress(0.5)
                try Data("update".utf8).write(to: destinationURL)
            }
        )
        let backend = try NativeBackendService(paths: paths, updateService: updateService)
        return AppModel(backend: backend, openDownloadedFile: openDownloadedFile)
    }

    private func makeBasicModel() throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperBasicModelTests-\(UUID().uuidString)", isDirectory: true)
        let backend = try NativeBackendService(paths: AppStoragePaths(rootURL: pathsRoot))
        return AppModel(backend: backend)
    }

    private func makePreviewModel(
        previewTransfer: @escaping PreviewFileService.TransferWriter
    ) throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperPreviewModelTests-\(UUID().uuidString)", isDirectory: true)
        let backend = try NativeBackendService(
            paths: AppStoragePaths(rootURL: pathsRoot),
            previewTransfer: previewTransfer
        )
        return AppModel(backend: backend)
    }

    private func makeBatchPreviewModel(
        searchHandler: @escaping @Sendable (PaperSourceQuery) async throws -> SourceSearchResult
    ) throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperBatchPreviewModelTests-\(UUID().uuidString)", isDirectory: true)
        let backend = try NativeBackendService(
            paths: AppStoragePaths(rootURL: pathsRoot),
            sourceRegistryBuilder: { _ in
                SourceRegistry(
                    sources: [ModelTestStubSource(id: .frankcie, searchHandler: searchHandler)],
                    automaticOrder: [.frankcie]
                )
            }
        )
        return AppModel(backend: backend)
    }

    private func makePaperFile(filename: String) -> PaperFile {
        PaperFile(
            filename: filename,
            url: URL(string: "https://example.test/\(filename)")!,
            year: 2024,
            season: "Jun",
            paperType: "QP",
            subjectCode: "9709",
            number: "12",
            label: "Paper 1",
            sourceID: .frankcie
        )
    }

    private func makeValidPreviewPDFData() throws -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 4, height: 4)).fill()
        image.unlockFocus()

        let document = PDFDocument()
        guard let page = PDFPage(image: image) else {
            throw XCTSkip("Unable to create PDF preview test page")
        }
        document.insert(page, at: 0)
        return try XCTUnwrap(document.dataRepresentation())
    }

    private func makeModelWithCachedSubjects(_ subjects: [Subject]) throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperSubjectLoadModelTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        try SearchCacheStore(paths: paths).save(subjects, source: .automatic, key: "subjects")
        let backend = try NativeBackendService(paths: paths)
        return AppModel(backend: backend)
    }

    private func makeManualSubjectListUnsupportedModel(sourceID: PaperSourceID) throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperManualSubjectListUnsupportedTests-\(UUID().uuidString)", isDirectory: true)
        let backend = try NativeBackendService(
            paths: AppStoragePaths(rootURL: pathsRoot),
            sourceRegistryBuilder: { _ in
                SourceRegistry(
                    sources: [ModelTestStubSource(id: sourceID) { _ in
                        SourceSearchResult(sourceID: sourceID, components: [])
                    }],
                    automaticOrder: [sourceID]
                )
            }
        )
        return AppModel(backend: backend)
    }

    private func makePersistentModel(initialSettings: DownloadSettings) async throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperSettingsModelTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let backend = try NativeBackendService(paths: paths)
        try backend.saveSettings(initialSettings)

        let model = AppModel(backend: backend)
        await model.loadSettings()
        return model
    }

    private static func releaseJSON(tag: String) -> Data {
        let version = tag.replacingOccurrences(of: "v", with: "")
        return """
        {
          "tag_name": "\(tag)",
          "name": "C-Paper Native \(version)",
          "html_url": "https://github.com/yimingwu425/C-Paper/releases/tag/\(tag)",
          "assets": [
            {
              "name": "C-Paper-Native-\(version)-standalone-20260604.dmg",
              "content_type": "application/x-apple-diskimage",
              "browser_download_url": "https://github.com/yimingwu425/C-Paper/releases/download/\(tag)/C-Paper-Native-\(version)-standalone-20260604.dmg"
            }
          ]
        }
        """.data(using: .utf8)!
    }
}

private struct DiagnosticTestError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private actor UpdateCallCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private final class ModelTestStubSource: PaperSource, @unchecked Sendable {
    let id: PaperSourceID
    private let searchHandler: @Sendable (PaperSourceQuery) async throws -> SourceSearchResult

    init(
        id: PaperSourceID,
        searchHandler: @escaping @Sendable (PaperSourceQuery) async throws -> SourceSearchResult
    ) {
        self.id = id
        self.searchHandler = searchHandler
    }

    func search(_ query: PaperSourceQuery) async throws -> SourceSearchResult {
        try await searchHandler(query)
    }

    func healthCheck() async -> SourceHealth {
        SourceHealth(sourceID: id, status: .available)
    }
}

private final class CountedUpdateNetworkClient: NetworkClientProtocol, @unchecked Sendable {
    let data: Data
    let counter: UpdateCallCounter

    init(data: Data, counter: UpdateCallCounter) {
        self.data = data
        self.counter = counter
    }

    func data(for request: URLRequest) async throws -> Data {
        await counter.increment()
        return data
    }
}

private final class URLRecorder {
    private var recordedURLs: [URL] = []

    func record(_ url: URL) {
        recordedURLs.append(url)
    }

    func lastValue() -> URL? {
        recordedURLs.last
    }

    func values() -> [URL] {
        recordedURLs
    }
}

private final class MutableBoolBox: @unchecked Sendable {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}

private actor UpdateDownloadCoordinator {
    private var didReportProgress = false
    private var progressWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func recordProgress() {
        didReportProgress = true
        let waiters = progressWaiters
        progressWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForProgress() async {
        if didReportProgress {
            return
        }

        await withCheckedContinuation { continuation in
            progressWaiters.append(continuation)
        }
    }

    func waitForFinishPermission() async {
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }

    func allowFinish() {
        let continuation = finishContinuation
        finishContinuation = nil
        continuation?.resume()
    }
}

private actor PreviewModelLoadCoordinator {
    private var startedFilenames: Set<String> = []
    private var startWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var allowWaiters: [String: CheckedContinuation<Void, Never>] = [:]

    func recordStart(_ filename: String) {
        startedFilenames.insert(filename)
        let waiters = startWaiters.removeValue(forKey: filename) ?? []
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilStarted(_ filename: String) async {
        if startedFilenames.contains(filename) {
            return
        }

        await withCheckedContinuation { continuation in
            startWaiters[filename, default: []].append(continuation)
        }
    }

    func waitUntilAllowed(_ filename: String) async {
        await withCheckedContinuation { continuation in
            allowWaiters[filename] = continuation
        }
    }

    func allow(_ filename: String) {
        let continuation = allowWaiters.removeValue(forKey: filename)
        continuation?.resume()
    }
}
