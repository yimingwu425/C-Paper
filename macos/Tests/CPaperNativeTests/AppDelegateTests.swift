import AppKit
import XCTest
@testable import CPaperNativeApp

@MainActor
final class AppDelegateTests: XCTestCase {
    func testApplicationDidFinishLaunchingInstallsMenuOnlyOnceAcrossRepeatedStartupCalls() throws {
        resetApplicationState()
        let delegate = AppDelegate()

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let firstMenu = try XCTUnwrap(NSApplication.shared.mainMenu)
        let firstWindow = try XCTUnwrap(NSApplication.shared.windows.first)

        delegate.showMainWindow()

        XCTAssertTrue(NSApplication.shared.mainMenu === firstMenu)
        XCTAssertEqual(NSApplication.shared.windows.count, 1)
        XCTAssertTrue(NSApplication.shared.windows.first === firstWindow)
        resetApplicationState()
    }

    func testShowMainWindowInstallsMenuWhenCalledBeforeLaunchCallback() throws {
        resetApplicationState()
        let delegate = AppDelegate()

        delegate.showMainWindow()

        XCTAssertNotNil(NSApplication.shared.mainMenu)
        XCTAssertEqual(NSApplication.shared.windows.count, 1)
        XCTAssertEqual(NSApplication.shared.windows.first?.title, "C-Paper")
        resetApplicationState()
    }

    private func resetApplicationState() {
        let app = NSApplication.shared
        app.windows.forEach { window in
            window.orderOut(nil)
            window.close()
        }
        app.mainMenu = nil
        app.servicesMenu = nil
        app.windowsMenu = nil
        app.helpMenu = nil
    }
}
