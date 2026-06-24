import AppKit
@testable import CPaperNativeApp
import XCTest

@MainActor
final class AppMenuCommandCenterTests: XCTestCase {
    override func tearDown() {
        MainActor.assumeIsolated {
            ReadyRootMenuBindings.unbind(commandCenter: AppMenuCommandCenter.shared)
        }
        super.tearDown()
    }

    func testDispatchInvokesBoundHandlerForCommand() {
        let center = AppMenuCommandCenter()
        var received: [AppMenuCommand] = []

        center.bind(
            handler: { command in
                received.append(command)
            },
            canPerform: { _ in true }
        )

        center.dispatch(.showSearch)

        XCTAssertEqual(received, [.showSearch])
    }

    func testDispatchIsNoOpWhenUnbound() {
        let center = AppMenuCommandCenter()
        let item = NSMenuItem(title: "搜索", action: #selector(AppMenuCommandCenter.dispatchMenuItem(_:)), keyEquivalent: "1")
        item.target = center
        item.representedObject = AppMenuCommand.showSearch

        center.dispatchMenuItem(item)

        XCTAssertFalse(center.canPerform(.showSearch))
    }

    func testUnbindDisablesProductCommands() {
        let center = AppMenuCommandCenter()

        center.bind(
            handler: { _ in },
            canPerform: { _ in true }
        )
        XCTAssertTrue(center.canPerform(.showDownloads))

        center.unbind()

        XCTAssertFalse(center.canPerform(.showDownloads))
        XCTAssertFalse(center.canPerform(.checkForUpdates))
    }

    func testValidateMenuItemUsesRepresentedObjectCommand() {
        let center = AppMenuCommandCenter()
        let allowedCommand = AppMenuCommand.showBatch
        let deniedCommand = AppMenuCommand.refreshCurrentView

        center.bind(
            handler: { _ in },
            canPerform: { command in
                command == allowedCommand
            }
        )

        let allowedItem = NSMenuItem(title: "批量", action: #selector(AppMenuCommandCenter.dispatchMenuItem(_:)), keyEquivalent: "2")
        allowedItem.target = center
        allowedItem.representedObject = allowedCommand

        let deniedItem = NSMenuItem(title: "刷新当前视图", action: #selector(AppMenuCommandCenter.dispatchMenuItem(_:)), keyEquivalent: "r")
        deniedItem.target = center
        deniedItem.representedObject = deniedCommand

        XCTAssertTrue(center.validateMenuItem(allowedItem))
        XCTAssertFalse(center.validateMenuItem(deniedItem))
    }

    func testReadyBindingDispatchesCommandsIntoModelAndWorkspaceTargets() throws {
        let center = AppMenuCommandCenter()
        let model = try makeBasicModel()
        var openedURLs: [URL] = []
        var didShowAboutPanel = false

        ReadyRootMenuBindings.bind(
            model: model,
            commandCenter: center,
            environment: .init(
                showAboutPanel: { didShowAboutPanel = true },
                openURL: { openedURLs.append($0) }
            )
        )

        center.dispatch(.showBatch)
        center.dispatch(.showDownloads)
        center.dispatch(.showSettings)
        center.dispatch(.showAbout)
        center.dispatch(.openWebsite)
        center.dispatch(.openGitHub)
        center.dispatch(.reportIssue)

        XCTAssertTrue(model.isSettingsPresented)
        XCTAssertEqual(model.route, .downloads)
        XCTAssertTrue(didShowAboutPanel)
        XCTAssertEqual(
            openedURLs,
            [
                ReadyRootMenuBindings.websiteURL,
                ReadyRootMenuBindings.gitHubURL,
                ReadyRootMenuBindings.issueURL,
            ]
        )
    }

    func testReadyBindingUnbindDisablesCommandsAgain() throws {
        let center = AppMenuCommandCenter()
        let model = try makeBasicModel()

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        XCTAssertTrue(center.canPerform(.showSearch))

        ReadyRootMenuBindings.unbind(commandCenter: center)

        XCTAssertFalse(center.canPerform(.showSearch))
        center.dispatch(.showSettings)
        XCTAssertFalse(model.isSettingsPresented)
    }

    func testReadyBindingDisablesRefreshWhileLoading() throws {
        let center = AppMenuCommandCenter()
        let model = try makeBasicModel()
        model.isLoading = true

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)

        XCTAssertFalse(center.canPerform(.refreshCurrentView))
        XCTAssertTrue(center.canPerform(.showDownloads))
    }

    func testReadyBindingDisablesManualUpdateCheckWhileCheckingOrDownloading() throws {
        let center = AppMenuCommandCenter()
        let model = try makeBasicModel()

        model.updateStatus = .checking
        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        XCTAssertFalse(center.canPerform(.checkForUpdates))

        model.updateStatus = .downloading(
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
                destinationURL: URL(fileURLWithPath: "/tmp/C-Paper-Native.dmg")
            )
        )
        XCTAssertFalse(center.canPerform(.checkForUpdates))

        model.updateStatus = .idle
        XCTAssertTrue(center.canPerform(.checkForUpdates))
    }

    func testReadyBindingDisablesCopyDiagnosticWithoutLatestDiagnostic() throws {
        let center = AppMenuCommandCenter()
        let model = try makeBasicModel()

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        XCTAssertFalse(center.canPerform(.copyLatestDiagnostic))

        _ = model.recordDiagnostic(context: .general, message: "boom")
        XCTAssertTrue(center.canPerform(.copyLatestDiagnostic))
    }

    func testReadyBindingTreatsCreatableSaveDirectoryAsRevealableButDisablesInvalidPath() throws {
        let center = AppMenuCommandCenter()
        let model = try makeBasicModel()
        let missingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperMissingMenuDirectory-\(UUID().uuidString)", isDirectory: true)
        model.settings.saveDirectory = missingDirectory.path

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        XCTAssertTrue(center.canPerform(.revealSaveDirectory))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperMenuDirectory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        model.settings.saveDirectory = directory.path

        XCTAssertTrue(center.canPerform(.revealSaveDirectory))

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperMenuDirectoryFile-\(UUID().uuidString).txt", isDirectory: false)
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("blocked".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        model.settings.saveDirectory = fileURL.path

        XCTAssertFalse(center.canPerform(.revealSaveDirectory))
    }

    func testInstalledRefreshMenuItemRunsSearchWorkflowOnSearchRoute() async throws {
        let center = AppMenuCommandCenter()
        let file = makePaperFile(filename: "9709_s24_qp_12.pdf")
        let model = try makeSearchCapableModel(files: [file])
        model.selectedSubject = Subject(code: "9709", name: "Mathematics")
        model.route = .search

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        let menu = installMenu(commandCenter: center)
        let item = try XCTUnwrap(menu.item(withCommand: .refreshCurrentView))

        center.dispatchMenuItem(item)

        await waitUntil("menu refresh command loads search results on search route") {
            model.searchResults.first?.filename == file.filename
                && model.searchResultSourceSummary?.contains("FrankCIE") == true
                && model.route == .search
        }

        XCTAssertNil(model.errorMessage)
    }

    func testInstalledRefreshMenuItemRunsBatchWorkflowOnBatchRoute() async throws {
        let center = AppMenuCommandCenter()
        let file = makePaperFile(filename: "9709_s24_ms_12.pdf")
        let model = try makeSearchCapableModel(files: [file])
        model.selectedSubject = Subject(code: "9709", name: "Mathematics")
        model.route = .batch
        model.batchYearFrom = 2024
        model.batchYearTo = 2024
        model.batchSeasons = [.jun]
        model.batchPaperGroups = [1]

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        let menu = installMenu(commandCenter: center)
        let item = try XCTUnwrap(menu.item(withCommand: .refreshCurrentView))

        center.dispatchMenuItem(item)

        await waitUntil("menu refresh command loads batch preview on batch route") {
            model.batchPreview.first?.filename == file.filename
                && model.batchPreviewSourceSummary?.contains("FrankCIE") == true
                && model.route == .batch
        }

        XCTAssertNil(model.errorMessage)
    }

    func testInstalledShowDownloadsMenuItemRoutesAndRefreshesRecoveredSession() async throws {
        let center = AppMenuCommandCenter()
        let model = try makeRecoveredInterruptedDownloadModel()
        model.route = .search

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        let menu = installMenu(commandCenter: center)
        let item = try XCTUnwrap(menu.item(withCommand: .showDownloads))

        center.dispatchMenuItem(item)

        await waitUntil("menu downloads command routes and refreshes recovered download state") {
            model.route == .downloads
                && model.downloadRecoveryNotice != nil
                && model.downloadRecoverySummary != nil
                && model.downloads.first?.workflowTag == .recoveredInterruptedSession
        }

        XCTAssertNil(model.errorMessage)
        model.pollTask?.cancel()
    }

    func testInstalledWorkflowMenuItemsStayBlockedWhileSettingsSheetIsPresented() throws {
        let center = AppMenuCommandCenter()
        let model = try makeBasicModel()
        model.route = .search
        model.isSettingsPresented = true

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        let menu = installMenu(commandCenter: center)
        let refreshItem = try XCTUnwrap(menu.item(withCommand: .refreshCurrentView))
        let batchItem = try XCTUnwrap(menu.item(withCommand: .showBatch))
        let downloadsItem = try XCTUnwrap(menu.item(withCommand: .showDownloads))
        let settingsItem = try XCTUnwrap(menu.item(withCommand: .showSettings))

        XCTAssertFalse(center.validateMenuItem(refreshItem))
        XCTAssertFalse(center.validateMenuItem(batchItem))
        XCTAssertFalse(center.validateMenuItem(downloadsItem))
        XCTAssertFalse(center.validateMenuItem(settingsItem))

        center.dispatchMenuItem(batchItem)
        center.dispatchMenuItem(downloadsItem)
        center.dispatchMenuItem(refreshItem)

        XCTAssertEqual(model.route, .search)
        XCTAssertTrue(model.isSettingsPresented)
        XCTAssertFalse(model.isLoading)
    }

    func testInstalledWorkflowMenuItemsStayBlockedWhilePendingUpdatePromptIsVisible() throws {
        let center = AppMenuCommandCenter()
        let model = try makeBasicModel()
        model.route = .search
        model.pendingUpdatePrompt = AppUpdateRelease(
            version: "6.0.4",
            tagName: "v6.0.4",
            name: "C-Paper Native 6.0.4",
            htmlURL: URL(string: "https://example.com/release")!,
            assetName: "C-Paper-Native.dmg",
            downloadURL: URL(string: "https://example.com/C-Paper-Native.dmg")!
        )

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        let menu = installMenu(commandCenter: center)
        let refreshItem = try XCTUnwrap(menu.item(withCommand: .refreshCurrentView))
        let downloadsItem = try XCTUnwrap(menu.item(withCommand: .showDownloads))
        let settingsItem = try XCTUnwrap(menu.item(withCommand: .showSettings))

        XCTAssertFalse(center.validateMenuItem(refreshItem))
        XCTAssertFalse(center.validateMenuItem(downloadsItem))
        XCTAssertFalse(center.validateMenuItem(settingsItem))

        center.dispatchMenuItem(downloadsItem)
        center.dispatchMenuItem(refreshItem)

        XCTAssertEqual(model.route, .search)
        XCTAssertNotNil(model.pendingUpdatePrompt)
        XCTAssertFalse(model.isLoading)
    }

    func testReadyBindingKeepsDiagnosticCommandAvailableWhileErrorAlertBlocksWorkflowCommands() throws {
        let center = AppMenuCommandCenter()
        let model = try makeBasicModel()
        model.route = .search
        _ = model.recordDiagnostic(context: .general, message: "menu gated error")
        model.errorMessage = "发生错误"

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)

        XCTAssertFalse(center.canPerform(.refreshCurrentView))
        XCTAssertFalse(center.canPerform(.showDownloads))
        XCTAssertFalse(center.canPerform(.showSettings))
        XCTAssertTrue(center.canPerform(.copyLatestDiagnostic))
    }

    func testInstalledCopyLatestDiagnosticMenuItemStillWorksWhileErrorAlertBlocksWorkflowCommands() throws {
        let center = AppMenuCommandCenter()
        let model = try makeBasicModel()
        let home = NSHomeDirectory()
        _ = model.recordDiagnostic(
            context: .update,
            message: "blocked at \(home)/Downloads/C-Paper.dmg via http://alice:secret@127.0.0.1:7890?token=abc123"
        )
        model.errorMessage = "发生错误"

        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        defer {
            if let original {
                pasteboard.setString(original, forType: .string)
            } else {
                pasteboard.clearContents()
            }
        }

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        let menu = installMenu(commandCenter: center)
        let copyItem = try XCTUnwrap(menu.item(withCommand: .copyLatestDiagnostic))
        let refreshItem = try XCTUnwrap(menu.item(withCommand: .refreshCurrentView))
        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .ready(model)
        let view = RootView(bootCoordinator: coordinator)

        XCTAssertTrue(center.validateMenuItem(copyItem))
        XCTAssertFalse(center.validateMenuItem(refreshItem))
        XCTAssertNoThrow(try view.inspect().find(text: "发生错误"))

        center.dispatchMenuItem(copyItem)

        let copied = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertTrue(copied.contains("Area: 更新"))
        XCTAssertTrue(copied.contains("~/Downloads/C-Paper.dmg"))
        XCTAssertTrue(copied.contains("http://<redacted>@127.0.0.1:7890?token=<redacted>"))
        XCTAssertFalse(copied.contains("alice:secret"))
        XCTAssertFalse(copied.contains("abc123"))
        XCTAssertFalse(copied.contains(home))
        XCTAssertEqual(model.errorMessage, "发生错误")
    }

    func testInstalledRevealSupportDirectoryMenuItemEscalatesOutOfRootErrorAlertIntoVisibleSupportNotice() throws {
        let center = AppMenuCommandCenter()
        let model = try makeBasicModel()
        let supportDirectoryURL = URL(fileURLWithPath: model.supportDirectoryPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: supportDirectoryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("blocked".utf8).write(to: supportDirectoryURL)
        defer { try? FileManager.default.removeItem(at: supportDirectoryURL) }
        model.errorMessage = "发生错误"

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        let menu = installMenu(commandCenter: center)
        let supportItem = try XCTUnwrap(menu.item(withCommand: .revealSupportDirectory))
        let refreshItem = try XCTUnwrap(menu.item(withCommand: .refreshCurrentView))
        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .ready(model)
        let view = RootView(bootCoordinator: coordinator)

        XCTAssertTrue(center.validateMenuItem(supportItem))
        XCTAssertFalse(center.validateMenuItem(refreshItem))
        XCTAssertNoThrow(try view.inspect().find(text: "发生错误"))

        center.dispatchMenuItem(supportItem)

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.supportDirectoryNotice?.message, "支持文件夹无法打开，请检查应用支持目录权限。")
        XCTAssertEqual(model.lastDiagnostic?.context, .supportDirectory)
        XCTAssertNoThrow(try view.inspect().find(text: "支持文件夹无法打开，请检查应用支持目录权限。"))
        XCTAssertNoThrow(try view.inspect().find(button: "重试打开"))
    }

    func testInstalledCopyLatestDiagnosticMenuItemCopiesRedactedLatestDiagnostic() throws {
        let center = AppMenuCommandCenter()
        let model = try makeBasicModel()
        let home = NSHomeDirectory()
        _ = model.recordDiagnostic(
            context: .update,
            message: "update failed at \(home)/Downloads/C-Paper.dmg via http://alice:secret@127.0.0.1:7890?token=abc123"
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

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        let menu = installMenu(commandCenter: center)
        let item = try XCTUnwrap(menu.item(withCommand: .copyLatestDiagnostic))

        center.dispatchMenuItem(item)

        let copied = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertTrue(copied.contains("Area: 更新"))
        XCTAssertTrue(copied.contains("~/Downloads/C-Paper.dmg"))
        XCTAssertTrue(copied.contains("http://<redacted>@127.0.0.1:7890?token=<redacted>"))
        XCTAssertFalse(copied.contains("alice:secret"))
        XCTAssertFalse(copied.contains("abc123"))
        XCTAssertFalse(copied.contains(home))
    }

    func testInstalledRevealSupportDirectoryMenuItemEscalatesIntoVisibleSupportNotice() throws {
        let center = AppMenuCommandCenter()
        let model = try makeBasicModel()
        let supportDirectoryURL = URL(fileURLWithPath: model.supportDirectoryPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: supportDirectoryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("blocked".utf8).write(to: supportDirectoryURL)
        defer { try? FileManager.default.removeItem(at: supportDirectoryURL) }

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        let menu = installMenu(commandCenter: center)
        let item = try XCTUnwrap(menu.item(withCommand: .revealSupportDirectory))
        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .ready(model)
        let view = RootView(bootCoordinator: coordinator)

        XCTAssertTrue(center.validateMenuItem(item))

        center.dispatchMenuItem(item)

        XCTAssertEqual(model.supportDirectoryNotice?.message, "支持文件夹无法打开，请检查应用支持目录权限。")
        XCTAssertEqual(model.lastDiagnostic?.context, .supportDirectory)
        XCTAssertNoThrow(try view.inspect().find(text: "支持文件夹无法打开，请检查应用支持目录权限。"))
        XCTAssertNoThrow(try view.inspect().find(button: "重试打开"))
    }

    func testInstalledCheckForUpdatesMenuItemSurfacesVisibleRetryNoticeAfterFailure() async throws {
        let center = AppMenuCommandCenter()
        let model = try makeUpdateCheckFailingModel()

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        let menu = installMenu(commandCenter: center)
        let item = try XCTUnwrap(menu.item(withCommand: .checkForUpdates))
        let coordinator = AppBootCoordinator(autoStart: false)
        coordinator.phase = .ready(model)
        let view = RootView(bootCoordinator: coordinator)

        XCTAssertTrue(center.validateMenuItem(item))

        center.dispatchMenuItem(item)

        await waitUntil("menu check for updates command surfaces retryable root update notice") {
            model.updateNotice?.action == .retryCheck
                && model.lastDiagnostic?.context == .update
                && model.errorMessage == nil
        }

        XCTAssertEqual(model.updateNotice?.message, "响应无效：检查更新失败")
        XCTAssertNoThrow(try view.inspect().find(text: "更新操作需要处理"))
        XCTAssertNoThrow(try view.inspect().find(button: "重新检查"))
    }

    func testInstalledRevealSaveDirectoryMenuItemCreatesMissingDirectoryWithoutNotice() throws {
        let center = AppMenuCommandCenter()
        let model = try makeBasicModel()
        let missingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperMenuCreateDirectory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: missingDirectory) }
        model.settings.saveDirectory = missingDirectory.path

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        let menu = installMenu(commandCenter: center)
        let item = try XCTUnwrap(menu.item(withCommand: .revealSaveDirectory))

        XCTAssertTrue(center.validateMenuItem(item))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingDirectory.path))

        center.dispatchMenuItem(item)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: missingDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertNil(model.saveDirectoryNotice)
        XCTAssertNil(model.errorMessage)
    }
}

private extension AppMenuCommandCenterTests {
    func installMenu(commandCenter: AppMenuCommandCenter) -> NSMenu {
        let app = NSApplication.shared
        app.mainMenu = nil
        app.servicesMenu = nil
        app.windowsMenu = nil
        app.helpMenu = nil
        return AppMenuController(commandCenter: commandCenter).install()
    }

    func makeBasicModel() throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperMenuCommandCenterTests-\(UUID().uuidString)", isDirectory: true)
        let backend = try NativeBackendService(paths: AppStoragePaths(rootURL: pathsRoot))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: pathsRoot)
        }
        return AppModel(backend: backend)
    }

    func makeSearchCapableModel(files: [PaperFile]) throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperMenuSearchTests-\(UUID().uuidString)", isDirectory: true)
        let components = files.map(makeMenuSourceComponent)
        let backend = try NativeBackendService(
            paths: AppStoragePaths(rootURL: pathsRoot),
            sourceRegistryBuilder: { _ in
                SourceRegistry(
                    sources: [
                        MenuWorkflowStubSource(
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
        addTeardownBlock {
            try? FileManager.default.removeItem(at: pathsRoot)
        }
        return AppModel(backend: backend)
    }

    func makeUpdateCheckFailingModel() throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperMenuUpdateFailure-\(UUID().uuidString)", isDirectory: true)
        let updateService = UpdateService(
            currentVersion: "6.0.3",
            updatesDirectory: pathsRoot,
            networkClientFactory: { _ in
                MenuFailingUpdateNetworkClient(error: BackendError.invalidResponse("检查更新失败"))
            }
        )
        let backend = try NativeBackendService(
            paths: AppStoragePaths(rootURL: pathsRoot),
            updateService: updateService
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: pathsRoot)
        }
        return AppModel(backend: backend)
    }

    func makeRecoveredInterruptedDownloadModel() throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperMenuRecoveredDownloads-\(UUID().uuidString)", isDirectory: true)
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
        addTeardownBlock {
            try? FileManager.default.removeItem(at: pathsRoot)
        }
        return AppModel(backend: backend)
    }

    func makePaperFile(filename: String) -> PaperFile {
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

    func waitUntil(
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
}

private extension NSMenu {
    func item(withTitle title: String) -> NSMenuItem? {
        items.first(where: { $0.title == title })
    }

    func item(withCommand command: AppMenuCommand) -> NSMenuItem? {
        for item in items {
            if item.representedObject as? AppMenuCommand == command {
                return item
            }
            if let submenu = item.submenu, let nested = submenu.item(withCommand: command) {
                return nested
            }
        }
        return nil
    }
}

private final class MenuWorkflowStubSource: PaperSource, @unchecked Sendable {
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

private final class MenuFailingUpdateNetworkClient: NetworkClientProtocol, @unchecked Sendable {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func data(for request: URLRequest) async throws -> Data {
        throw error
    }
}

private func makeMenuSourceComponent(from file: PaperFile) -> PaperComponent {
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
