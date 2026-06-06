import AppKit
import XCTest
@testable import CPaperNativeApp

@MainActor
final class AppMenuCommandCenterTests: XCTestCase {
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
}
