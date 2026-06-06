import AppKit

@MainActor
final class AppMenuController {
    private let commandCenter: AppMenuCommandCenter
    private let appName: String

    init(commandCenter: AppMenuCommandCenter = .shared, appName: String = "C-Paper") {
        self.commandCenter = commandCenter
        self.appName = appName
    }

    @discardableResult
    func install() -> NSMenu {
        let app = NSApplication.shared
        let mainMenu = NSMenu(title: appName)

        let appSubmenu = NSMenu(title: appName)
        let appItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        appItem.submenu = appSubmenu
        mainMenu.addItem(appItem)

        addCommandItem(.showAbout, title: "关于 \(appName)", to: appSubmenu)
        appSubmenu.addItem(.separator())
        addCommandItem(.showSettings, title: "设置...", key: ",", to: appSubmenu)
        addCommandItem(.checkForUpdates, title: "检查更新...", to: appSubmenu)
        appSubmenu.addItem(.separator())

        let servicesMenu = NSMenu(title: "服务")
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        servicesItem.submenu = servicesMenu
        appSubmenu.addItem(servicesItem)
        app.servicesMenu = servicesMenu

        appSubmenu.addItem(.separator())
        appSubmenu.addItem(makeStandardItem(title: "隐藏 \(appName)", action: #selector(NSApplication.hide(_:)), key: "h"))
        appSubmenu.addItem(makeStandardItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]))
        appSubmenu.addItem(makeStandardItem(title: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:))))
        appSubmenu.addItem(.separator())
        appSubmenu.addItem(makeStandardItem(title: "退出 \(appName)", action: #selector(NSApplication.terminate(_:)), key: "q"))

        let fileSubmenu = NSMenu(title: "文件")
        let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        fileItem.submenu = fileSubmenu
        mainMenu.addItem(fileItem)
        addCommandItem(.revealSaveDirectory, title: "显示下载文件夹", to: fileSubmenu)
        addCommandItem(.copyLatestDiagnostic, title: "复制最近诊断", to: fileSubmenu)
        addCommandItem(.revealSupportDirectory, title: "显示支持目录", to: fileSubmenu)

        let editSubmenu = NSMenu(title: "编辑")
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = editSubmenu
        mainMenu.addItem(editItem)
        editSubmenu.addItem(makeStandardItem(title: "撤销", action: Selector(("undo:")), key: "z"))
        editSubmenu.addItem(makeStandardItem(title: "重做", action: Selector(("redo:")), key: "Z", modifiers: [.command, .shift]))
        editSubmenu.addItem(.separator())
        editSubmenu.addItem(makeStandardItem(title: "剪切", action: #selector(NSText.cut(_:)), key: "x"))
        editSubmenu.addItem(makeStandardItem(title: "复制", action: #selector(NSText.copy(_:)), key: "c"))
        editSubmenu.addItem(makeStandardItem(title: "粘贴", action: #selector(NSText.paste(_:)), key: "v"))
        editSubmenu.addItem(makeStandardItem(title: "全选", action: #selector(NSText.selectAll(_:)), key: "a"))

        let viewSubmenu = NSMenu(title: "显示")
        let viewItem = NSMenuItem(title: "显示", action: nil, keyEquivalent: "")
        viewItem.submenu = viewSubmenu
        mainMenu.addItem(viewItem)
        addCommandItem(.refreshCurrentView, title: "刷新当前视图", key: "r", to: viewSubmenu)
        viewSubmenu.addItem(.separator())
        addCommandItem(.showSearch, title: "搜索", key: "1", to: viewSubmenu)
        addCommandItem(.showBatch, title: "批量", key: "2", to: viewSubmenu)
        addCommandItem(.showDownloads, title: "下载", key: "3", to: viewSubmenu)

        let windowSubmenu = NSMenu(title: "窗口")
        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        windowItem.submenu = windowSubmenu
        mainMenu.addItem(windowItem)
        windowSubmenu.addItem(makeStandardItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        windowSubmenu.addItem(makeStandardItem(title: "缩放", action: #selector(NSWindow.performZoom(_:))))
        windowSubmenu.addItem(.separator())
        windowSubmenu.addItem(makeStandardItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), key: "w"))
        windowSubmenu.addItem(makeStandardItem(title: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:))))
        app.windowsMenu = windowSubmenu

        let helpSubmenu = NSMenu(title: "帮助")
        let helpItem = NSMenuItem(title: "帮助", action: nil, keyEquivalent: "")
        helpItem.submenu = helpSubmenu
        mainMenu.addItem(helpItem)
        addCommandItem(.openWebsite, title: "C-Paper 网站", to: helpSubmenu)
        addCommandItem(.openGitHub, title: "GitHub 仓库", to: helpSubmenu)
        addCommandItem(.reportIssue, title: "报告问题", to: helpSubmenu)
        app.helpMenu = helpSubmenu

        app.mainMenu = mainMenu
        return mainMenu
    }

    private func addCommandItem(
        _ command: AppMenuCommand,
        title: String,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command],
        to menu: NSMenu
    ) {
        let item = NSMenuItem(
            title: title,
            action: #selector(AppMenuCommandCenter.dispatchMenuItem(_:)),
            keyEquivalent: key
        )
        item.target = commandCenter
        item.representedObject = command
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        menu.addItem(item)
    }

    private func makeStandardItem(
        title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = nil
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        return item
    }
}
