import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.finishLaunching()
delegate.showMainWindow()
app.activate(ignoringOtherApps: true)
withExtendedLifetime(delegate) {
    app.run()
}
