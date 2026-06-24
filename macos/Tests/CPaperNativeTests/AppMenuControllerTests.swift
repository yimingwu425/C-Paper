import AppKit
import XCTest
@testable import CPaperNativeApp

@MainActor
final class AppMenuControllerTests: XCTestCase {
    func testInstallBuildsExpectedTopLevelMenusAndAppWiring() throws {
        let app = NSApplication.shared
        app.mainMenu = nil
        app.servicesMenu = nil
        app.windowsMenu = nil
        app.helpMenu = nil
        let controller = AppMenuController(commandCenter: AppMenuCommandCenter())

        let menu = controller.install()

        XCTAssertEqual(menu.items.map(\.title), ["C-Paper", "文件", "编辑", "显示", "窗口", "帮助"])
        XCTAssertTrue(app.mainMenu === menu)
        XCTAssertEqual(app.windowsMenu?.title, "窗口")
        XCTAssertEqual(app.helpMenu?.title, "帮助")

        let appMenu = try XCTUnwrap(menu.item(withTitle: "C-Paper")?.submenu)
        XCTAssertNotNil(appMenu.item(withTitle: "关于 C-Paper"))
        XCTAssertNotNil(appMenu.item(withTitle: "设置..."))
        XCTAssertNotNil(appMenu.item(withTitle: "检查更新..."))
        XCTAssertNotNil(appMenu.item(withTitle: "服务"))
        XCTAssertNotNil(appMenu.item(withTitle: "隐藏 C-Paper"))
        XCTAssertNotNil(appMenu.item(withTitle: "退出 C-Paper"))
        XCTAssertTrue(app.servicesMenu === appMenu.item(withTitle: "服务")?.submenu)

        let fileMenu = try XCTUnwrap(menu.item(withTitle: "文件")?.submenu)
        XCTAssertNotNil(fileMenu.item(withTitle: "显示下载文件夹"))
        XCTAssertNotNil(fileMenu.item(withTitle: "复制最近诊断"))
        XCTAssertNotNil(fileMenu.item(withTitle: "显示支持目录"))

        let editMenu = try XCTUnwrap(menu.item(withTitle: "编辑")?.submenu)
        XCTAssertNotNil(editMenu.item(withTitle: "撤销"))
        XCTAssertNotNil(editMenu.item(withTitle: "重做"))
        XCTAssertNotNil(editMenu.item(withTitle: "剪切"))
        XCTAssertNotNil(editMenu.item(withTitle: "复制"))
        XCTAssertNotNil(editMenu.item(withTitle: "粘贴"))
        XCTAssertNotNil(editMenu.item(withTitle: "全选"))

        let viewMenu = try XCTUnwrap(menu.item(withTitle: "显示")?.submenu)
        XCTAssertNotNil(viewMenu.item(withTitle: "刷新当前视图"))
        XCTAssertNotNil(viewMenu.item(withTitle: "搜索"))
        XCTAssertNotNil(viewMenu.item(withTitle: "批量"))
        XCTAssertNotNil(viewMenu.item(withTitle: "下载"))

        let helpMenu = try XCTUnwrap(menu.item(withTitle: "帮助")?.submenu)
        XCTAssertNotNil(helpMenu.item(withTitle: "C-Paper 网站"))
        XCTAssertNotNil(helpMenu.item(withTitle: "GitHub 仓库"))
        XCTAssertNotNil(helpMenu.item(withTitle: "报告问题"))
    }

    func testInstallAssignsRequiredKeyboardShortcuts() throws {
        let app = NSApplication.shared
        app.mainMenu = nil
        app.servicesMenu = nil
        app.windowsMenu = nil
        app.helpMenu = nil
        let controller = AppMenuController(commandCenter: AppMenuCommandCenter())
        let menu = controller.install()

        let appMenu = try XCTUnwrap(menu.item(withTitle: "C-Paper")?.submenu)
        assertShortcut(for: try XCTUnwrap(appMenu.item(withTitle: "设置...")), key: ",", modifiers: [.command])
        assertShortcut(for: try XCTUnwrap(appMenu.item(withTitle: "退出 C-Paper")), key: "q", modifiers: [.command])

        let editMenu = try XCTUnwrap(menu.item(withTitle: "编辑")?.submenu)
        assertStandardResponderAction(for: try XCTUnwrap(editMenu.item(withTitle: "撤销")), expectedActionName: "undo:")
        assertStandardResponderAction(for: try XCTUnwrap(editMenu.item(withTitle: "重做")), expectedActionName: "redo:")
        assertStandardResponderAction(for: try XCTUnwrap(editMenu.item(withTitle: "剪切")), expectedActionName: "cut:")
        assertStandardResponderAction(for: try XCTUnwrap(editMenu.item(withTitle: "复制")), expectedActionName: "copy:")
        assertStandardResponderAction(for: try XCTUnwrap(editMenu.item(withTitle: "粘贴")), expectedActionName: "paste:")
        assertStandardResponderAction(for: try XCTUnwrap(editMenu.item(withTitle: "全选")), expectedActionName: "selectAll:")
        assertShortcut(for: try XCTUnwrap(editMenu.item(withTitle: "剪切")), key: "x", modifiers: [.command])
        assertShortcut(for: try XCTUnwrap(editMenu.item(withTitle: "复制")), key: "c", modifiers: [.command])
        assertShortcut(for: try XCTUnwrap(editMenu.item(withTitle: "粘贴")), key: "v", modifiers: [.command])
        assertShortcut(for: try XCTUnwrap(editMenu.item(withTitle: "全选")), key: "a", modifiers: [.command])

        let windowMenu = try XCTUnwrap(menu.item(withTitle: "窗口")?.submenu)
        assertShortcut(for: try XCTUnwrap(windowMenu.item(withTitle: "关闭窗口")), key: "w", modifiers: [.command])

        let viewMenu = try XCTUnwrap(menu.item(withTitle: "显示")?.submenu)
        assertShortcut(for: try XCTUnwrap(viewMenu.item(withTitle: "搜索")), key: "1", modifiers: [.command])
        assertShortcut(for: try XCTUnwrap(viewMenu.item(withTitle: "批量")), key: "2", modifiers: [.command])
        assertShortcut(for: try XCTUnwrap(viewMenu.item(withTitle: "下载")), key: "3", modifiers: [.command])
    }

    private func assertShortcut(for item: NSMenuItem, key: String, modifiers: NSEvent.ModifierFlags, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(item.keyEquivalent, key, file: file, line: line)
        XCTAssertEqual(item.keyEquivalentModifierMask.intersection([.command, .option, .control, .shift]), modifiers, file: file, line: line)
    }

    private func assertStandardResponderAction(for item: NSMenuItem, expectedActionName: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(item.target, file: file, line: line)
        XCTAssertEqual(NSStringFromSelector(item.action ?? #selector(NSResponder.noResponder(for:))), expectedActionName, file: file, line: line)
    }
}

private extension NSMenu {
    func item(withTitle title: String) -> NSMenuItem? {
        items.first(where: { $0.title == title })
    }
}
