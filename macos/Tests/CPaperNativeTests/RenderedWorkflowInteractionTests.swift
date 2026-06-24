import SwiftUI
import Foundation
@preconcurrency import Combine
import ViewInspector
import XCTest
@testable import CPaperNativeApp

extension InspectableSheet: PopupPresenter { }
extension InspectablePopover: PopupPresenter { }
extension Inspection: InspectionEmissary { }

@MainActor
final class RenderedWorkflowInteractionTests: XCTestCase {
    func testSidebarViewTapDownloadsRouteSwitchesModelRoute() throws {
        let model = try makeBasicModel()
        model.route = .search

        let view = SidebarView(model: model)

        try view.inspect().find(button: "下载").tap()

        XCTAssertEqual(model.route, .downloads)
    }

    func testSettingsViewRendersSupportAndSettingsNoticesFromModelState() throws {
        let model = try makeBasicModel()
        model.supportDirectoryNotice = SupportDirectoryNotice(
            diagnostic: SupportDiagnostic(context: .general, message: "支持目录失败")
        )
        model.settingsNotice = SettingsNotice(
            diagnostic: SupportDiagnostic(context: .settings, message: "保存设置失败")
        )

        let view = SettingsView(model: model)
        let inspection = try view.inspect()

        XCTAssertNoThrow(try inspection.find(text: "支持目录失败"))
        XCTAssertNoThrow(try inspection.find(text: "保存设置失败"))
    }

    func testSettingsViewCopyDiagnosticButtonCopiesRedactedReportText() throws {
        let model = try makeBasicModel()
        let home = NSHomeDirectory()
        model.settingsNotice = SettingsNotice(
            diagnostic: SupportDiagnostic(
                context: .settings,
                message: "保存失败 at \(home)/Downloads/file.pdf via http://alice:secret@127.0.0.1:7890"
            )
        )

        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        defer {
            if let original {
                pasteboard.setString(original, forType: .string)
            } else {
                pasteboard.clearContents()
            }
        }

        let view = SettingsView(model: model)
        try view.inspect().find(button: "复制诊断").tap()

        let copied = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertTrue(copied.contains("Area: 设置"))
        XCTAssertTrue(copied.contains("~/Downloads/file.pdf"))
        XCTAssertTrue(copied.contains("http://<redacted>@127.0.0.1:7890"))
        XCTAssertFalse(copied.contains("alice:secret"))
        XCTAssertFalse(copied.contains(home))
    }

    func testRootViewStartupFailureCopyDiagnosticButtonCopiesFailureDiagnosticText() throws {
        let home = NSHomeDirectory()
        let failure = AppBootFailure(
            message: "无法启动 C-Paper",
            diagnosticText: """
            C-Paper Diagnostics
            Area: 启动
            Message: failed at ~/Downloads/file.log via http://<redacted>@127.0.0.1:7890
            Original Home: \(home)
            """,
            supportDirectoryURL: nil
        )
        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .failed(failure)

        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        defer {
            if let original {
                pasteboard.setString(original, forType: .string)
            } else {
                pasteboard.clearContents()
            }
        }

        let view = RootView(bootCoordinator: coordinator)
        try view.inspect().find(button: "复制诊断信息").tap()

        let copied = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertEqual(copied, failure.diagnosticText)
        XCTAssertTrue(copied.contains("Area: 启动"))
        XCTAssertTrue(copied.contains("http://<redacted>@127.0.0.1:7890"))
    }

    func testRootViewStartupFailureRevealSupportDirectoryFailureShowsContextualAlert() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedStartupFailure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let blockedSupportURL = tempDirectory.appendingPathComponent("Support", isDirectory: true)
        try Data("blocked".utf8).write(to: blockedSupportURL)

        let failure = AppBootFailure(
            message: "无法启动 C-Paper",
            diagnosticText: "startup diagnostic",
            supportDirectoryURL: blockedSupportURL
        )
        let sut = StartupFailureView(failure: failure, onRetry: {})
        let exp1 = sut.inspection.inspect { view in
            try view.zStack().find(button: "显示支持文件夹").tap()
        }
        let exp2 = sut.inspection.inspect(after: 0.1) { view in
            let alert = try view.zStack().alert()
            XCTAssertEqual(try alert.title().string(), "无法显示支持文件夹")
            let message = try alert.message().text().string()
            XCTAssertTrue(message.contains("无法显示支持文件夹"))
            XCTAssertTrue(message.contains(SupportDiagnostic.redact(blockedSupportURL.path)))
            XCTAssertTrue(message.contains("原因："))
        }

        ViewHosting.host(view: sut)
        defer { ViewHosting.expel() }
        wait(for: [exp1, exp2], timeout: 1.0)
    }

    func testStartupFailureViewRetryButtonInvokesRetryAction() throws {
        var retryCount = 0
        let sut = StartupFailureView(
            failure: AppBootFailure(
                message: "无法启动 C-Paper",
                diagnosticText: "startup diagnostic",
                supportDirectoryURL: nil
            ),
            onRetry: {
                retryCount += 1
            }
        )
        let exp1 = sut.inspection.inspect { view in
            try view.zStack().find(button: "重试").tap()
        }
        let exp2 = sut.inspection.inspect(after: 0.1) { _ in
            XCTAssertEqual(retryCount, 1)
        }

        ViewHosting.host(view: sut)
        defer { ViewHosting.expel() }
        wait(for: [exp1, exp2], timeout: 1.0)
    }

    func testUpdateSettingsSectionTapOpenDMGInvokesModelOpenAction() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedUpdateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let downloadedFileURL = tempDirectory.appendingPathComponent("C-Paper-Native.dmg", isDirectory: false)
        try Data("update".utf8).write(to: downloadedFileURL)

        var openedURLs: [URL] = []
        let model = try makeBasicModel(openDownloadedFile: {
            openedURLs.append($0)
            return true
        })
        let release = sampleRelease()
        model.updateStatus = .downloaded(
            DownloadedUpdateState(
                release: release,
                fileURL: downloadedFileURL,
                installState: .downloaded,
                origin: .currentSession
            )
        )

        let view = UpdateSettingsSection(model: model)

        try view.inspect().find(button: "打开 DMG").tap()

        XCTAssertEqual(openedURLs, [downloadedFileURL])
    }

    func testUpdateSettingsSectionDisablesButtonsWhileDownloading() throws {
        let model = try makeBasicModel()
        model.updateStatus = .downloading(
            UpdateDownloadState(
                release: sampleRelease(),
                progress: 0.4,
                destinationURL: URL(fileURLWithPath: "/tmp/C-Paper-Native.dmg")
            )
        )

        let view = UpdateSettingsSection(model: model)
        let inspection = try view.inspect()

        XCTAssertTrue(try inspection.find(button: "检查更新").isDisabled())
        XCTAssertTrue(try inspection.find(button: "下载更新").isDisabled())
        XCTAssertThrowsError(try inspection.find(button: "打开 DMG"))
    }

    func testUpdateSettingsSectionTapDownloadUpdateDownloadsAndOpensDMG() async throws {
        var openedURLs: [URL] = []
        let model = try makeUpdateCapableModel(openDownloadedFile: {
            openedURLs.append($0)
            return true
        })
        await model.checkForUpdates(source: .manual)

        let view = UpdateSettingsSection(model: model)

        XCTAssertNoThrow(try view.inspect().find(button: "下载更新"))
        try view.inspect().find(button: "下载更新").tap()

        await waitUntil("settings update download action downloads artifact and opens it") {
            guard case let .downloaded(state) = model.updateStatus else {
                return false
            }
            return state.origin == .currentSession
                && openedURLs == [state.fileURL]
                && ((try? String(contentsOf: state.fileURL)) == "update")
        }

        XCTAssertNil(model.updateNotice)
        XCTAssertNil(model.errorMessage)
    }

    func testUpdateSettingsSectionRevealDownloadedFileMissingArtifactShowsRetryNotice() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedUpdateRevealMissing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let missingFileURL = tempDirectory.appendingPathComponent("C-Paper-Native.dmg", isDirectory: false)
        let release = sampleRelease()
        let model = try makeBasicModel()
        model.updateStatus = .downloaded(
            DownloadedUpdateState(
                release: release,
                fileURL: missingFileURL,
                installState: .downloaded,
                origin: .restoredArtifact
            )
        )

        let view = UpdateSettingsSection(model: model)

        XCTAssertNoThrow(try view.inspect().find(button: "显示文件"))
        try view.inspect().find(button: "显示文件").tap()

        XCTAssertEqual(model.updateNotice?.message, "已下载的更新 DMG 不存在，请重新下载。")
        XCTAssertEqual(model.updateNotice?.action, .retryDownload)
        XCTAssertEqual(model.lastDiagnostic?.context, .update)
        XCTAssertFalse(model.updateStatus.canAccessDownloadedFile)
        XCTAssertNoThrow(try view.inspect().find(text: "已下载的更新 DMG 不存在，请重新下载。"))
        XCTAssertNoThrow(try view.inspect().find(button: "重试下载"))
    }

    func testRootViewToolbarDownloadButtonSwitchesRoute() throws {
        let model = try makeBasicModel()
        model.route = .search
        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .ready(model)
        let view = RootView(bootCoordinator: coordinator)

        let toolbar = try view.inspect().find(ViewType.NavigationSplitView.self).toolbar()
        try toolbar.itemGroup().button(1).tap()

        XCTAssertEqual(model.route, .downloads)
    }

    func testSearchViewTapSearchLoadsResultsAndSourceSummary() async throws {
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let model = try makeSearchCapableModel(files: [file])
        model.selectedSubject = Subject(code: "9709", name: "Mathematics")
        model.route = .search

        let view = SearchView(model: model)

        try view.inspect().find(button: "搜索").tap()
        await waitUntil("search button loads result files and source summary") {
            model.searchResults.first?.filename == file.filename
                && model.searchResultSourceID == .frankcie
                && model.searchResultSourceSummary?.contains("FrankCIE") == true
        }

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.sourceNotice)
    }

    func testSearchFilterPanelSubmitRunsSearchWorkflow() async throws {
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let model = try makeSearchCapableModel(files: [file])
        model.selectedSubject = Subject(code: "9709", name: "Mathematics")
        model.route = .search

        let view = SearchFilterPanel(model: model)

        try view.inspect().find(ViewType.VStack.self).callOnSubmit()
        await waitUntil("search submit loads result files and source summary") {
            model.searchResults.first?.filename == file.filename
                && model.searchResultSourceID == .frankcie
                && model.searchResultSourceSummary?.contains("FrankCIE") == true
        }

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.sourceNotice)
    }

    func testSearchFilterPanelSubjectPickerSelectionClearsManualCodeThroughRenderedPopoverFlow() throws {
        let biology = CPaperNativeApp.Subject(code: "0610", name: "Biology")
        let mathematics = CPaperNativeApp.Subject(code: "9709", name: "Mathematics")
        let selectionBox = SubjectSelectionBox(selection: nil, manualCode: "9709")
        let sut = SubjectPicker(
            subjects: [biology, mathematics],
            selection: selectionBox.selectionBinding,
            manualCode: selectionBox.manualCodeBinding
        )
        let exp1 = sut.inspection.inspect { view in
            try view.find(button: "选择科目").tap()
        }
        let exp2 = sut.inspection.inspect(after: 0.1) { view in
            let popover = try view.find(button: "选择科目").popover()
            XCTAssertEqual(try popover.find(ViewType.TextField.self).input(), "")
            try popover.find(ViewType.TextField.self).setInput("bio")
            XCTAssertNoThrow(try popover.find(text: biology.displayName))
            XCTAssertThrowsError(try popover.find(text: mathematics.displayName))
            try popover.find(button: biology.displayName).tap()
        }
        let exp3 = sut.inspection.inspect(after: 0.2) { view in
            _ = view
            XCTAssertEqual(selectionBox.selection, biology)
            XCTAssertEqual(selectionBox.manualCode, "")
            XCTAssertThrowsError(try view.find(button: "选择科目").popover())
        }

        ViewHosting.host(view: sut)
        defer { ViewHosting.expel() }
        wait(for: [exp1, exp2, exp3], timeout: 1.0)
    }

    func testSearchFilterPanelSubjectPickerDismissResetsPopoverQueryBeforeReopen() throws {
        let biology = CPaperNativeApp.Subject(code: "0610", name: "Biology")
        let mathematics = CPaperNativeApp.Subject(code: "9709", name: "Mathematics")
        let selectionBox = SubjectSelectionBox(selection: nil, manualCode: "")
        let sut = SubjectPicker(
            subjects: [biology, mathematics],
            selection: selectionBox.selectionBinding,
            manualCode: selectionBox.manualCodeBinding
        )
        let exp1 = sut.inspection.inspect { view in
            try view.find(button: "选择科目").tap()
        }
        let exp2 = sut.inspection.inspect(after: 0.1) { view in
            let firstPopover = try view.find(button: "选择科目").popover()
            try firstPopover.find(ViewType.TextField.self).setInput("bio")
            XCTAssertNoThrow(try firstPopover.find(text: biology.displayName))
            XCTAssertThrowsError(try firstPopover.find(text: mathematics.displayName))
            try firstPopover.dismiss()
        }
        let exp3 = sut.inspection.inspect(after: 0.2) { view in
            XCTAssertThrowsError(try view.find(button: "选择科目").popover())
        }
        let exp4 = sut.inspection.inspect(after: 0.3) { view in
            XCTAssertThrowsError(try view.find(button: "选择科目").popover())
            try view.find(button: "选择科目").tap()
        }
        let exp5 = sut.inspection.inspect(after: 0.4) { view in
            let reopenedPopover = try view.find(button: "选择科目").popover()
            XCTAssertEqual(try reopenedPopover.find(ViewType.TextField.self).input(), "")
            XCTAssertNoThrow(try reopenedPopover.find(text: biology.displayName))
            XCTAssertNoThrow(try reopenedPopover.find(text: mathematics.displayName))
        }

        ViewHosting.host(view: sut)
        defer { ViewHosting.expel() }
        wait(for: [exp1, exp2, exp3, exp4, exp5], timeout: 1.2)
    }

    func testSearchViewRetrySearchNoticeActionLoadsResultsAfterFailure() async throws {
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let attempts = RenderedSearchAttemptCounter()
        let component = makeRenderedSourceComponent(from: file)
        let model = try makeSearchCapableModel {
            let current = await attempts.next()
            if current == 1 {
                throw PaperSourceError.sourceUnavailable("FrankCIE 暂不可用")
            }
            return SourceSearchResult(
                sourceID: .frankcie,
                components: [component]
            )
        }
        model.selectedSubject = Subject(code: "9709", name: "Mathematics")
        model.route = .search

        let view = SearchView(model: model)

        try view.inspect().find(button: "搜索").tap()
        await waitUntil("search failure surfaces retry notice") {
            model.sourceNotice?.action == .retrySearch
        }

        XCTAssertTrue(model.searchResults.isEmpty)
        XCTAssertNoThrow(try view.inspect().find(button: "重试搜索"))

        try view.inspect().find(button: "重试搜索").tap()
        await waitUntil("retry search loads results after visible notice action") {
            model.searchResults.first?.filename == file.filename
                && model.searchResultSourceSummary?.contains("FrankCIE") == true
                && model.sourceNotice == nil
        }

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
    }

    func testSearchViewTapDownloadCurrentResultsStartsDownloadAndSwitchesRoute() async throws {
        let model = try makeDownloadingModel()
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        model.searchResults = [file]
        model.searchGroups = [model.backendGroup(for: file)]
        model.route = .search

        let view = SearchView(model: model)

        try view.inspect().find(button: "下载当前结果").tap()
        await waitUntil("search download switches to downloads route and queues the file") {
            model.route == .downloads && model.downloads.first?.filename == file.filename
        }

        XCTAssertNil(model.downloadNotice)
        XCTAssertNil(model.errorMessage)
        model.pollTask?.cancel()
    }

    func testSearchViewRetryDownloadNoticeActionRestartsFailedDownloadAndClearsNotice() async throws {
        let setup = try makeRetryableDownloadStartModel()
        let model = setup.model
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        model.searchResults = [file]
        model.searchGroups = [model.backendGroup(for: file)]
        model.route = .search

        let view = SearchView(model: model)

        try view.inspect().find(button: "下载当前结果").tap()
        await waitUntil("search download failure surfaces retry notice") {
            model.downloadNotice?.action == .retrySearchDownload
        }

        XCTAssertNoThrow(try view.inspect().find(button: "重试下载"))
        XCTAssertTrue(model.downloads.isEmpty)

        try FileManager.default.removeItem(at: setup.pathsRoot)
        try FileManager.default.createDirectory(at: setup.pathsRoot, withIntermediateDirectories: true)

        try view.inspect().find(button: "重试下载").tap()
        await waitUntil("search download retry starts queue and clears notice") {
            guard let item = model.downloads.first else {
                return false
            }
            return model.route == .downloads
                && model.downloadNotice == nil
                && item.filename == file.filename
                && ((try? String(contentsOf: URL(fileURLWithPath: item.savePath))) == "ok")
        }

        XCTAssertNil(model.errorMessage)
        model.pollTask?.cancel()
    }

    func testRootViewSearchWorkflowSearchesThenDownloadsAcrossRouteTransition() async throws {
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let model = try makeSearchAndDownloadCapableModel(files: [file])
        model.selectedSubject = Subject(code: "9709", name: "Mathematics")
        model.route = .search

        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .ready(model)
        let view = RootView(bootCoordinator: coordinator)
        let toolbar = try view.inspect().find(ViewType.NavigationSplitView.self).toolbar()

        try toolbar.itemGroup().button(0).tap()
        await waitUntil("root search workflow refresh action loads results from the rendered root surface") {
            model.searchResults.first?.filename == file.filename
                && model.searchResultSourceSummary?.contains("FrankCIE") == true
                && model.route == .search
        }

        XCTAssertNoThrow(try view.inspect().find(button: "下载当前结果"))
        try view.inspect().find(button: "下载当前结果").tap()

        await waitUntil("root search workflow switches into downloads after visible download action") {
            model.route == .downloads
                && model.downloads.first?.filename == file.filename
        }

        XCTAssertNoThrow(try view.inspect().find(text: "下载队列"))
        XCTAssertNil(model.errorMessage)
        model.pollTask?.cancel()
    }

    func testBatchViewRetryPreviewNoticeActionLoadsFilesAfterFailure() async throws {
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let attempts = RenderedSearchAttemptCounter()
        let component = makeRenderedSourceComponent(from: file)
        let model = try makeSearchCapableModel {
            let current = await attempts.next()
            if current == 1 {
                throw PaperSourceError.sourceUnavailable("FrankCIE 暂不可用")
            }
            return SourceSearchResult(
                sourceID: .frankcie,
                components: [component]
            )
        }
        model.selectedSubject = Subject(code: "9709", name: "Mathematics")
        model.route = .batch
        model.batchYearFrom = 2024
        model.batchYearTo = 2024
        model.batchSeasons = [.jun]
        model.batchPaperGroups = [1]

        let view = BatchView(model: model)

        try view.inspect().find(button: "预览清单").tap()
        await waitUntil("batch preview failure surfaces retry notice") {
            model.sourceNotice?.action == .retryBatchPreview
        }

        XCTAssertTrue(model.batchPreview.isEmpty)
        XCTAssertNoThrow(try view.inspect().find(button: "重试预览"))

        try view.inspect().find(button: "重试预览").tap()
        await waitUntil("retry batch preview loads files after visible notice action") {
            model.batchPreview.first?.filename == file.filename
                && model.batchPreviewSourceSummary?.contains("FrankCIE") == true
                && model.sourceNotice == nil
        }

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
    }

    func testBatchFilterPanelSubmitRunsPreviewWorkflow() async throws {
        let file = makePaperFile(filename: "9709_s24_ms_12.pdf")
        let model = try makeSearchCapableModel(files: [file])
        model.selectedSubject = Subject(code: "9709", name: "Mathematics")
        model.route = .batch
        model.batchYearFrom = 2024
        model.batchYearTo = 2024
        model.batchSeasons = [.jun]
        model.batchPaperGroups = [1]

        let view = BatchFilterPanel(model: model)

        try view.inspect().find(ViewType.VStack.self).callOnSubmit()
        await waitUntil("batch submit loads preview files and source summary") {
            model.batchPreview.first?.filename == file.filename
                && model.batchPreviewSourceSummary?.contains("FrankCIE") == true
        }

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.sourceNotice)
    }

    func testBatchFilterPanelTapDownloadStartsBatchQueueAndSwitchesRoute() async throws {
        let model = try makeDownloadingModel()
        let file = makePaperFile(filename: "9709_s24_ms_12.pdf")
        model.batchGroups = [model.backendGroup(for: file)]
        model.batchPreview = [file]
        model.route = .batch

        let view = BatchFilterPanel(model: model)

        try view.inspect().find(button: "选择目录并下载").tap()
        await waitUntil("batch download switches to downloads route and queues the file") {
            model.route == .downloads && model.downloads.first?.filename == file.filename
        }

        XCTAssertNil(model.downloadNotice)
        XCTAssertNil(model.errorMessage)
        model.pollTask?.cancel()
    }

    func testBatchViewRetryDownloadNoticeActionRestartsFailedBatchDownloadAndClearsNotice() async throws {
        let setup = try makeRetryableDownloadStartModel()
        let model = setup.model
        let file = makePaperFile(filename: "9709_s24_ms_12.pdf")
        model.batchPreview = [file]
        model.batchGroups = [model.backendGroup(for: file)]
        model.route = .batch

        let view = BatchView(model: model)

        try view.inspect().find(button: "选择目录并下载").tap()
        await waitUntil("batch download failure surfaces retry notice") {
            model.downloadNotice?.action == .retryBatchDownload
        }

        XCTAssertNoThrow(try view.inspect().find(button: "重试下载"))
        XCTAssertTrue(model.downloads.isEmpty)

        try FileManager.default.removeItem(at: setup.pathsRoot)
        try FileManager.default.createDirectory(at: setup.pathsRoot, withIntermediateDirectories: true)

        try view.inspect().find(button: "重试下载").tap()
        await waitUntil("batch download retry starts queue and clears notice") {
            guard let item = model.downloads.first else {
                return false
            }
            return model.route == .downloads
                && model.downloadNotice == nil
                && item.filename == file.filename
                && ((try? String(contentsOf: URL(fileURLWithPath: item.savePath))) == "ok")
        }

        XCTAssertNil(model.errorMessage)
        model.pollTask?.cancel()
    }

    func testRootViewBatchWorkflowPreviewsThenDownloadsAcrossRouteTransition() async throws {
        let file = makePaperFile(filename: "9709_s24_ms_12.pdf")
        let model = try makeSearchAndDownloadCapableModel(files: [file])
        model.selectedSubject = Subject(code: "9709", name: "Mathematics")
        model.route = .batch
        model.batchYearFrom = 2024
        model.batchYearTo = 2024
        model.batchSeasons = [.jun]
        model.batchPaperGroups = [1]

        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .ready(model)
        let view = RootView(bootCoordinator: coordinator)
        let toolbar = try view.inspect().find(ViewType.NavigationSplitView.self).toolbar()

        try toolbar.itemGroup().button(0).tap()
        await waitUntil("root batch workflow refresh action loads preview files from the rendered root surface") {
            model.batchPreview.first?.filename == file.filename
                && model.batchPreviewSourceSummary?.contains("FrankCIE") == true
                && model.route == .batch
        }

        XCTAssertNoThrow(try view.inspect().find(button: "选择目录并下载"))
        try view.inspect().find(button: "选择目录并下载").tap()

        await waitUntil("root batch workflow switches into downloads after visible batch action") {
            model.route == .downloads
                && model.downloads.first?.filename == file.filename
        }

        XCTAssertNoThrow(try view.inspect().find(text: "下载队列"))
        XCTAssertNil(model.errorMessage)
        model.pollTask?.cancel()
    }

    func testPDFPreviewViewRetryPreviewButtonResetsFailureStateAndBumpsRevision() throws {
        let model = try makeBasicModel()
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        model.selectedPreview = file
        model.previewLoadRevision = 3
        model.previewLoadState = .failed(
            PreviewFailureState(
                diagnostic: SupportDiagnostic(context: .preview, message: "预览缓存已损坏，请重试预览。"),
                suggestsRedownload: false
            )
        )

        let view = PDFPreviewView(model: model, file: file)

        try view.inspect().find(button: "重试预览").tap()

        XCTAssertEqual(model.previewLoadState, .idle)
        XCTAssertEqual(model.previewLoadRevision, 4)
    }

    func testPDFPreviewViewCopyDiagnosticButtonCopiesRedactedPreviewFailureReport() throws {
        let model = try makeBasicModel()
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let home = NSHomeDirectory()
        model.selectedPreview = file
        model.previewLoadState = .failed(
            PreviewFailureState(
                diagnostic: SupportDiagnostic(
                    context: .preview,
                    message: "预览失败 at \(home)/Library/Caches/C-Paper/9709_s24_qp_12.pdf via http://alice:secret@127.0.0.1:7890?token=abc123",
                    details: [
                        SupportDiagnosticDetail(label: "Filename", value: file.filename),
                        SupportDiagnosticDetail(label: "Local File", value: "\(home)/Library/Caches/C-Paper/9709_s24_qp_12.pdf")
                    ]
                ),
                suggestsRedownload: true
            )
        )

        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        defer {
            if let original {
                pasteboard.setString(original, forType: .string)
            } else {
                pasteboard.clearContents()
            }
        }

        let view = PDFPreviewView(model: model, file: file)

        XCTAssertNoThrow(try view.inspect().find(button: "复制诊断"))
        try view.inspect().find(button: "复制诊断").tap()

        let copied = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertTrue(copied.contains("Area: 预览"))
        XCTAssertTrue(copied.contains("~/Library/Caches/C-Paper/9709_s24_qp_12.pdf"))
        XCTAssertTrue(copied.contains("http://<redacted>@127.0.0.1:7890?token=<redacted>"))
        XCTAssertFalse(copied.contains("alice:secret"))
        XCTAssertFalse(copied.contains("abc123"))
        XCTAssertFalse(copied.contains(home))
    }

    func testPDFPreviewViewRedownloadButtonQueuesRepairDownloadAndRetriesPreview() async throws {
        let model = try makeDownloadingModel()
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        model.selectedPreview = file
        model.previewLoadRevision = 5
        model.previewLoadState = .failed(
            PreviewFailureState(
                diagnostic: SupportDiagnostic(context: .preview, message: "预览文件无法打开，请重新下载或在浏览器中打开。"),
                suggestsRedownload: true
            )
        )

        let view = PDFPreviewView(model: model, file: file)

        try view.inspect().find(button: "重新下载文件").tap()
        await waitUntil("preview repair queues download and retries preview") {
            model.downloads.first?.filename == file.filename
                && model.previewLoadState == .idle
                && model.previewLoadRevision == 6
        }

        XCTAssertNil(model.downloadNotice)
        XCTAssertNil(model.errorMessage)
        model.pollTask?.cancel()
    }

    func testRootViewPreviewFailureRevealSupportDirectoryActionShowsSupportNotice() throws {
        let model = try makeBasicModel()
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let supportDirectoryURL = URL(fileURLWithPath: model.supportDirectoryPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: supportDirectoryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("blocked".utf8).write(to: supportDirectoryURL)

        model.route = .search
        model.selectedPreview = file
        model.previewLoadState = .failed(
            PreviewFailureState(
                diagnostic: SupportDiagnostic(context: .preview, message: "预览缓存已损坏，请重试预览。"),
                suggestsRedownload: false
            )
        )

        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .ready(model)
        let view = RootView(bootCoordinator: coordinator)

        XCTAssertNoThrow(try view.inspect().find(button: "显示支持文件夹"))
        try view.inspect().find(button: "显示支持文件夹").tap()

        XCTAssertEqual(model.supportDirectoryNotice?.message, "支持文件夹无法打开，请检查应用支持目录权限。")
        XCTAssertEqual(model.lastDiagnostic?.context, .supportDirectory)
        XCTAssertNoThrow(try view.inspect().find(text: "支持文件夹无法打开，请检查应用支持目录权限。"))
    }

    func testRootViewToolbarSettingsButtonPresentsAndDismissesSettingsSheet() throws {
        let model = try makeBasicModel()
        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .ready(model)
        let view = RootView(bootCoordinator: coordinator)

        let root = try view.inspect().find(ViewType.NavigationSplitView.self)
        let toolbar = try root.toolbar()
        try toolbar.itemGroup().button(2).tap()

        XCTAssertTrue(model.isSettingsPresented)
        XCTAssertNoThrow(try root.sheet().find(text: "设置"))

        try root.sheet().dismiss()

        XCTAssertFalse(model.isSettingsPresented)
    }

    func testDownloadsSaveDirectoryNoticePrimaryActionPresentsSettingsSheet() throws {
        let model = try makeBasicModel()
        model.route = .downloads
        model.saveDirectoryNotice = SaveDirectoryNotice(
            diagnostic: SupportDiagnostic(context: .saveDirectory, message: "下载文件夹当前不可用。"),
            action: .openSettings
        )

        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .ready(model)
        let view = RootView(bootCoordinator: coordinator)
        let root = try view.inspect().find(ViewType.NavigationSplitView.self)

        try root.find(button: "打开设置").tap()

        XCTAssertTrue(model.isSettingsPresented)
        XCTAssertNoThrow(try root.sheet().find(text: "设置"))
    }

    func testRootViewDownloadsRevealSaveDirectoryInvalidPathShowsSaveDirectoryNotice() throws {
        let model = try makeBasicModel()
        let blockedFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedBlockedSaveDirectory-\(UUID().uuidString).txt", isDirectory: false)
        FileManager.default.createFile(atPath: blockedFileURL.path, contents: Data("blocked".utf8))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: blockedFileURL)
        }

        model.route = .downloads
        model.settings.saveDirectory = blockedFileURL.path

        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .ready(model)
        let view = RootView(bootCoordinator: coordinator)
        let root = try view.inspect().find(ViewType.NavigationSplitView.self)

        XCTAssertNoThrow(try root.find(button: "显示文件夹"))
        try root.find(button: "显示文件夹").tap()

        XCTAssertEqual(model.saveDirectoryNotice?.action, .openSettings)
        XCTAssertEqual(model.lastDiagnostic?.context, .saveDirectory)
        XCTAssertEqual(model.saveDirectoryNotice?.message, "下载文件夹当前不可用，请先在设置中选择有效的保存目录。")
        XCTAssertNoThrow(try root.find(text: "下载文件夹当前不可用，请先在设置中选择有效的保存目录。"))
        XCTAssertNoThrow(try root.find(button: "打开设置"))
    }

    func testDownloadsViewRetryFailedButtonRestartsRecoveredInterruptedDownload() async throws {
        let setup = try await makeRecoveredInterruptedDownloadModel()
        let model = setup.model

        let view = DownloadsView(model: model)

        XCTAssertNoThrow(try view.inspect().find(button: "重试失败项"))
        try view.inspect().find(button: "重试失败项").tap()

        await waitUntil("downloads retry button clears recovery notice and completes restored task") {
            model.downloadRecoveryNotice == nil
                && model.downloadRecoverySummary == nil
                && model.downloads.first?.status == .done
                && ((try? String(contentsOf: setup.saveURL)) == "restored")
        }

        XCTAssertNil(model.errorMessage)
        model.pollTask?.cancel()
    }

    func testDownloadsViewCopyDiagnosticButtonCopiesLatestDownloadRecoveryReport() async throws {
        let setup = try await makeRecoveredInterruptedDownloadModel()
        let model = setup.model
        let expected = try XCTUnwrap(model.latestDiagnostic(for: .download))

        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        defer {
            if let original {
                pasteboard.setString(original, forType: .string)
            } else {
                pasteboard.clearContents()
            }
        }

        let view = DownloadsView(model: model)

        XCTAssertNoThrow(try view.inspect().find(button: "复制诊断"))
        try view.inspect().find(button: "复制诊断").tap()

        let copied = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertTrue(copied.contains("Area: 下载"))
        XCTAssertTrue(copied.contains(expected.message))
        XCTAssertTrue(copied.contains("recovered.pdf"))
        XCTAssertTrue(copied.contains("上次下载在应用退出前中断，请重试"))
        XCTAssertTrue(copied.contains("检查网络后重试"))
        XCTAssertEqual(copied, expected.reportText)

        model.pollTask?.cancel()
    }

    func testDownloadsViewCancelButtonCancelsRunningQueueAndKeepsFileUncommitted() async throws {
        let setup = try makeCancellableRunningDownloadModel()
        let model = setup.model
        model.searchGroups = [model.backendGroup(for: setup.file)]

        await model.startSearchDownload()
        await setup.coordinator.waitUntilStarted(setup.file.filename)
        await waitUntil("downloads view shows a running queue that can be cancelled") {
            model.downloadSnapshot.isRunning
                && model.activeDownloadCount == 1
                && model.downloads.first?.status == .downloading
        }

        let view = DownloadsView(model: model)

        XCTAssertNoThrow(try view.inspect().find(button: "取消"))
        try view.inspect().find(button: "取消").tap()

        await waitUntil("downloads cancel button marks the running queue cancelled") {
            !model.downloadSnapshot.isRunning
                && model.cancelledDownloadCount == 1
                && model.downloads.first?.status == .cancelled
        }

        await setup.coordinator.allow(setup.file.filename)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(model.downloads.first?.status, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.saveURL.path))
        XCTAssertNil(model.errorMessage)
        model.pollTask?.cancel()
    }

    func testDownloadsIntegrityNoticePrimaryActionRepairsMissingCompletedFile() async throws {
        let setup = try await makeMissingCompletedDownloadModel()
        let model = setup.model

        let view = DownloadsView(model: model)

        XCTAssertNoThrow(try view.inspect().find(button: "重新下载受影响文件"))
        try view.inspect().find(button: "重新下载受影响文件").tap()

        await waitUntil(
            "downloads integrity repair action restores missing completed file",
            timeoutNanoseconds: 3_000_000_000
        ) {
            model.downloadIntegrityNotice == nil
                && model.downloadIntegrityStatesByTaskID.isEmpty
                && model.downloads.first?.status == .done
                && ((try? String(contentsOf: setup.savedFileURL)) == "attempt-2")
        }

        XCTAssertNil(model.errorMessage)
        model.pollTask?.cancel()
    }

    func testRootViewErrorAlertDismissButtonClearsError() throws {
        let model = try makeBasicModel()
        _ = model.recordDiagnostic(context: .general, message: "支持诊断")
        model.errorMessage = "发生错误"

        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .ready(model)
        let view = RootView(bootCoordinator: coordinator)

        let alert = try view.inspect().find(ViewType.NavigationSplitView.self).alert(0)
        XCTAssertEqual(try alert.title().string(), "C-Paper")
        XCTAssertEqual(try alert.message().text().string(), "发生错误")
        try alert.dismiss()

        XCTAssertNil(model.errorMessage)
    }

    func testRootViewPendingUpdateAlertPrimaryActionOpensDownloadedDMG() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedRootAlertTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let downloadedFileURL = tempDirectory.appendingPathComponent("C-Paper-Native.dmg", isDirectory: false)
        try Data("update".utf8).write(to: downloadedFileURL)

        var openedURLs: [URL] = []
        let model = try makeBasicModel(openDownloadedFile: {
            openedURLs.append($0)
            return true
        })
        let release = sampleRelease()
        model.pendingUpdatePrompt = release
        model.updateStatus = .downloaded(
            DownloadedUpdateState(
                release: release,
                fileURL: downloadedFileURL,
                installState: .downloaded,
                origin: .restoredArtifact
            )
        )

        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .ready(model)
        let view = RootView(bootCoordinator: coordinator)

        let alert = try view.inspect().find(ViewType.NavigationSplitView.self).alert(1)
        XCTAssertEqual(try alert.title().string(), "发现新版本")
        XCTAssertTrue(try alert.message().text().string().contains("可直接打开安装"))
        XCTAssertEqual(
            try alert.actions().button(1).labelView().text().string(),
            "打开已下载更新"
        )

        try alert.actions().button(1).tap()

        XCTAssertEqual(openedURLs, [downloadedFileURL])
    }

    func testRootViewPendingUpdateAlertPrimaryActionDownloadsAndOpensUpdate() async throws {
        var openedURLs: [URL] = []
        let model = try makeUpdateCapableModel(openDownloadedFile: {
            openedURLs.append($0)
            return true
        })
        await model.checkForUpdates(source: .startup)

        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .ready(model)
        let view = RootView(bootCoordinator: coordinator)
        let alert = try view.inspect().find(ViewType.NavigationSplitView.self).alert(1)

        XCTAssertEqual(try alert.title().string(), "发现新版本")
        XCTAssertEqual(
            try alert.actions().button(1).labelView().text().string(),
            "下载更新"
        )

        try alert.actions().button(1).tap()
        await waitUntil("startup update prompt downloads artifact and opens it") {
            guard case let .downloaded(state) = model.updateStatus else {
                return false
            }
            return state.origin == .currentSession
                && openedURLs == [state.fileURL]
                && ((try? String(contentsOf: state.fileURL)) == "update")
        }

        XCTAssertNil(model.pendingUpdatePrompt)
        XCTAssertNil(model.updateNotice)
        XCTAssertNil(model.errorMessage)
    }

    func testRootViewUpdateNoticeRetryDownloadActionDownloadsAfterFailureAndClearsNotice() async throws {
        var openedURLs: [URL] = []
        let attempts = AttemptCounter()
        let model = try makeRetryableUpdateModel(
            attempts: attempts,
            openDownloadedFile: {
                openedURLs.append($0)
                return true
            }
        )
        await model.checkForUpdates(source: .manual)
        await model.downloadAvailableUpdate()

        await waitUntil("update download failure surfaces root retry notice") {
            model.updateNotice?.action == .retryDownload
        }

        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .ready(model)
        let view = RootView(bootCoordinator: coordinator)

        XCTAssertNoThrow(try view.inspect().find(button: "重试下载"))
        try view.inspect().find(button: "重试下载").tap()

        await waitUntil("update notice retry downloads artifact and clears notice") {
            guard case let .downloaded(state) = model.updateStatus else {
                return false
            }
            return model.updateNotice == nil
                && openedURLs == [state.fileURL]
                && ((try? String(contentsOf: state.fileURL)) == "update-attempt-2")
        }

        XCTAssertNil(model.pendingUpdatePrompt)
        XCTAssertNil(model.errorMessage)
    }

    private func makeBasicModel(
        openDownloadedFile: @escaping (URL) -> Bool = { _ in true },
        downloadManager: DownloadManager? = nil
    ) throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedWorkflowTests-\(UUID().uuidString)", isDirectory: true)
        let backend = try NativeBackendService(
            paths: AppStoragePaths(rootURL: pathsRoot),
            downloadManager: downloadManager
        )
        return AppModel(backend: backend, openDownloadedFile: openDownloadedFile)
    }

    private func makeDownloadingModel() throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedWorkflowDownloads-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let saveDirectory = pathsRoot.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        let manager = DownloadManager(
            sharedTransfer: { _, partialURL, _, _ in
                try Data("ok".utf8).write(to: partialURL)
            },
            sessionStore: DownloadSessionStore(paths: paths)
        )
        let model = try makeBasicModel(downloadManager: manager)
        model.settings.saveDirectory = saveDirectory.path
        return model
    }

    private func makeUpdateCapableModel(
        openDownloadedFile: @escaping (URL) -> Bool = { _ in true }
    ) throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedUpdateWorkflow-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let releaseData = """
        {
          "tag_name": "v6.0.6",
          "name": "C-Paper Native 6.0.6",
          "html_url": "https://github.com/yimingwu425/C-Paper/releases/tag/v6.0.6",
          "assets": [
            {
              "name": "C-Paper-Native-6.0.6-standalone-20260604.dmg",
              "content_type": "application/x-apple-diskimage",
              "browser_download_url": "https://github.com/yimingwu425/C-Paper/releases/download/v6.0.6/C-Paper-Native-6.0.6-standalone-20260604.dmg"
            }
          ]
        }
        """.data(using: .utf8)!
        let updateService = UpdateService(
            currentVersion: "6.0.3",
            updatesDirectory: pathsRoot,
            networkClientFactory: { _ in
                RenderedUpdateNetworkClient(data: releaseData)
            },
            downloadWriter: { _, destinationURL, _, progress in
                await progress(0.5)
                try Data("update".utf8).write(to: destinationURL)
            }
        )
        let backend = try NativeBackendService(paths: paths, updateService: updateService)
        let model = AppModel(backend: backend, openDownloadedFile: openDownloadedFile)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: pathsRoot)
        }
        return model
    }

    private func makeRetryableUpdateModel(
        attempts: AttemptCounter,
        openDownloadedFile: @escaping (URL) -> Bool = { _ in true }
    ) throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedRetryableUpdateWorkflow-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let releaseData = """
        {
          "tag_name": "v6.0.6",
          "name": "C-Paper Native 6.0.6",
          "html_url": "https://github.com/yimingwu425/C-Paper/releases/tag/v6.0.6",
          "assets": [
            {
              "name": "C-Paper-Native-6.0.6-standalone-20260604.dmg",
              "content_type": "application/x-apple-diskimage",
              "browser_download_url": "https://github.com/yimingwu425/C-Paper/releases/download/v6.0.6/C-Paper-Native-6.0.6-standalone-20260604.dmg"
            }
          ]
        }
        """.data(using: .utf8)!
        let updateService = UpdateService(
            currentVersion: "6.0.3",
            updatesDirectory: pathsRoot,
            networkClientFactory: { _ in
                RenderedUpdateNetworkClient(data: releaseData)
            },
            downloadWriter: { _, destinationURL, _, progress in
                let current = await attempts.next()
                await progress(0.5)
                if current == 1 {
                    throw BackendError.invalidResponse("首次更新下载失败")
                }
                try Data("update-attempt-\(current)".utf8).write(to: destinationURL)
            }
        )
        let backend = try NativeBackendService(paths: paths, updateService: updateService)
        let model = AppModel(backend: backend, openDownloadedFile: openDownloadedFile)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: pathsRoot)
        }
        return model
    }

    private func makeSearchAndDownloadCapableModel(files: [PaperFile]) throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedRootWorkflow-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let saveDirectory = pathsRoot.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        let components = files.map(makeRenderedSourceComponent)
        let manager = DownloadManager(
            sharedTransfer: { _, partialURL, _, _ in
                try Data("ok".utf8).write(to: partialURL)
            },
            sessionStore: DownloadSessionStore(paths: paths)
        )
        let backend = try NativeBackendService(
            paths: paths,
            downloadManager: manager,
            sourceRegistryBuilder: { _ in
                SourceRegistry(
                    sources: [
                        RenderedSearchStubSource(
                            searchHandler: { _ in
                                SourceSearchResult(
                                    sourceID: .frankcie,
                                    components: components
                                )
                            }
                        )
                    ],
                    automaticOrder: [.frankcie]
                )
            }
        )
        let model = AppModel(backend: backend)
        model.settings.saveDirectory = saveDirectory.path
        addTeardownBlock {
            try? FileManager.default.removeItem(at: pathsRoot)
        }
        return model
    }

    private func makeSearchCapableModel(files: [PaperFile]) throws -> AppModel {
        let components = files.map(makeRenderedSourceComponent)
        return try makeSearchCapableModel {
            SourceSearchResult(
                sourceID: .frankcie,
                components: components
            )
        }
    }

    private func makeSearchCapableModel(
        searchHandler: @escaping @Sendable () async throws -> SourceSearchResult
    ) throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedSearchWorkflow-\(UUID().uuidString)", isDirectory: true)
        let backend = try NativeBackendService(
            paths: AppStoragePaths(rootURL: pathsRoot),
            sourceRegistryBuilder: { _ in
                SourceRegistry(
                    sources: [
                        RenderedSearchStubSource(
                            searchHandler: { _ in
                                try await searchHandler()
                            }
                        )
                    ],
                    automaticOrder: [.frankcie]
                )
            }
        )
        let model = AppModel(backend: backend)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: pathsRoot)
        }
        return model
    }

    private func makeRetryableDownloadStartModel() throws -> (model: AppModel, pathsRoot: URL) {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedDownloadRetryWorkflow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: pathsRoot, withIntermediateDirectories: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let chosenDirectory = pathsRoot.appendingPathComponent("chosen", isDirectory: true)
        let invalidFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedDownloadRetryInvalid-\(UUID().uuidString).txt", isDirectory: false)
        FileManager.default.createFile(atPath: invalidFileURL.path, contents: Data("blocked".utf8))

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
        model.settings.saveDirectory = invalidFileURL.path

        try FileManager.default.removeItem(at: pathsRoot)
        FileManager.default.createFile(atPath: pathsRoot.path, contents: Data("blocked".utf8))

        addTeardownBlock {
            try? FileManager.default.removeItem(at: invalidFileURL)
            try? FileManager.default.removeItem(at: pathsRoot)
        }
        return (model, pathsRoot)
    }

    private func makeRecoveredInterruptedDownloadModel() async throws -> (model: AppModel, saveURL: URL) {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedRecoveredDownloads-\(UUID().uuidString)", isDirectory: true)
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
        addTeardownBlock {
            try? FileManager.default.removeItem(at: pathsRoot)
        }

        await model.refreshDownloads()
        return (model, saveURL)
    }

    private func makeCancellableRunningDownloadModel() throws -> (
        model: AppModel,
        file: PaperFile,
        saveURL: URL,
        coordinator: ControlledDownloadCoordinator
    ) {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedCancellableDownloads-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let saveDirectory = pathsRoot.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)

        let coordinator = ControlledDownloadCoordinator()
        let manager = DownloadManager(
            sharedTransfer: { sourceURL, partialURL, _, _ in
                let filename = sourceURL.lastPathComponent
                await coordinator.markStarted(filename)
                await coordinator.waitUntilAllowed(filename)
                try Data("late-payload".utf8).write(to: partialURL)
            },
            sessionStore: DownloadSessionStore(paths: paths)
        )
        let backend = try NativeBackendService(paths: paths, downloadManager: manager)
        let model = AppModel(backend: backend)
        model.settings.saveDirectory = saveDirectory.path

        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let saveURL = saveDirectory
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent(file.filename, isDirectory: false)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: pathsRoot)
        }

        return (model, file, saveURL, coordinator)
    }

    private func makeMissingCompletedDownloadModel() async throws -> (model: AppModel, savedFileURL: URL) {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRenderedMissingCompletedDownloads-\(UUID().uuidString)", isDirectory: true)
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
        for _ in 0..<200 {
            let snapshot = await manager.status()
            if !snapshot.isRunning {
                break
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        try FileManager.default.removeItem(at: savedFileURL)
        await model.refreshDownloads()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: pathsRoot)
        }

        return (model, savedFileURL)
    }

    private func makePaperFile(filename: String) -> PaperFile {
        PaperFile(
            filename: filename,
            url: URL(string: "https://example.com/\(filename)")!,
            year: 2024,
            season: "May/June",
            paperType: "QP",
            subjectCode: "9709",
            number: "12",
            label: "Question Paper",
            sourceID: .pastPapers
        )
    }

    private func waitUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollIntervalNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + .nanoseconds(Int(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        XCTFail("Timed out waiting for condition: \(description)")
    }

    private func sampleRelease() -> AppUpdateRelease {
        AppUpdateRelease(
            version: "6.0.6",
            tagName: "v6.0.6",
            name: "C-Paper 6.0.6",
            htmlURL: URL(string: "https://example.com/release")!,
            assetName: "C-Paper-Native-6.0.6.dmg",
            downloadURL: URL(string: "https://example.com/dmg")!
        )
    }
}

@MainActor
private final class SubjectSelectionBox: @unchecked Sendable {
    var selection: CPaperNativeApp.Subject?
    var manualCode: String

    init(selection: CPaperNativeApp.Subject?, manualCode: String) {
        self.selection = selection
        self.manualCode = manualCode
    }

    var selectionBinding: Binding<CPaperNativeApp.Subject?> {
        Binding(
            get: { self.selection },
            set: { self.selection = $0 }
        )
    }

    var manualCodeBinding: Binding<String> {
        Binding(
            get: { self.manualCode },
            set: { self.manualCode = $0 }
        )
    }
}

private final class RenderedUpdateNetworkClient: NetworkClientProtocol, @unchecked Sendable {
    let data: Data

    init(data: Data) {
        self.data = data
    }

    func data(for request: URLRequest) async throws -> Data {
        data
    }
}

private func makeRenderedSourceComponent(from file: PaperFile) -> PaperComponent {
    PaperComponent(
        sourceID: .frankcie,
        filename: file.filename,
        url: file.url,
        paperType: file.paperType ?? "QP",
        subjectCode: file.subjectCode,
        sy: "s24",
        number: file.number,
        label: file.label
    )
}

private final class RenderedSearchStubSource: PaperSource, @unchecked Sendable {
    let id: PaperSourceID = .frankcie
    private let searchHandler: @Sendable (PaperSourceQuery) async throws -> SourceSearchResult

    init(searchHandler: @escaping @Sendable (PaperSourceQuery) async throws -> SourceSearchResult) {
        self.searchHandler = searchHandler
    }

    func search(_ query: PaperSourceQuery) async throws -> SourceSearchResult {
        try await searchHandler(query)
    }

    func healthCheck() async -> SourceHealth {
        SourceHealth(sourceID: id, status: .available)
    }
}

private actor RenderedSearchAttemptCounter {
    private var count = 0

    func next() -> Int {
        count += 1
        return count
    }
}
