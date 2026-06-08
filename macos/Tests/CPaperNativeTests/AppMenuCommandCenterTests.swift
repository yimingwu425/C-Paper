import AppKit
import XCTest
@testable import CPaperNativeApp

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

        center.dispatch(.showSettings)
        center.dispatch(.showBatch)
        center.dispatch(.showDownloads)
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
                ReadyRootMenuBindings.issueURL
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

        model.updateStatus = .downloading(progress: 0.5)
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

    func testReadyBindingDisablesRevealSaveDirectoryWhenDirectoryIsNotUsable() throws {
        let center = AppMenuCommandCenter()
        let model = try makeBasicModel()
        model.settings.saveDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperMissingMenuDirectory-\(UUID().uuidString)", isDirectory: true)
            .path

        ReadyRootMenuBindings.bind(model: model, commandCenter: center)
        XCTAssertFalse(center.canPerform(.revealSaveDirectory))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperMenuDirectory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        model.settings.saveDirectory = directory.path

        XCTAssertTrue(center.canPerform(.revealSaveDirectory))
    }
}

private extension AppMenuCommandCenterTests {
    func makeBasicModel() throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperMenuCommandCenterTests-\(UUID().uuidString)", isDirectory: true)
        let backend = try NativeBackendService(paths: AppStoragePaths(rootURL: pathsRoot))
        return AppModel(backend: backend)
    }
}
