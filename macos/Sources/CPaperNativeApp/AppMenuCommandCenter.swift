import AppKit

@MainActor
final class AppMenuCommandCenter: NSObject, NSMenuItemValidation {
    static let shared = AppMenuCommandCenter()

    private var handler: ((AppMenuCommand) -> Void)?
    private var canPerformHandler: ((AppMenuCommand) -> Bool)?

    func bind(
        handler: @escaping (AppMenuCommand) -> Void,
        canPerform: @escaping (AppMenuCommand) -> Bool
    ) {
        self.handler = handler
        self.canPerformHandler = canPerform
    }

    func unbind() {
        handler = nil
        canPerformHandler = nil
    }

    func dispatch(_ command: AppMenuCommand) {
        guard canPerform(command) else { return }
        handler?(command)
    }

    func canPerform(_ command: AppMenuCommand) -> Bool {
        guard let canPerformHandler else { return false }
        return canPerformHandler(command)
    }

    @objc func dispatchMenuItem(_ sender: Any?) {
        guard
            let item = sender as? NSMenuItem,
            let command = item.representedObject as? AppMenuCommand
        else {
            return
        }

        dispatch(command)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = menuItem.representedObject as? AppMenuCommand else {
            return true
        }

        return canPerform(command)
    }
}
