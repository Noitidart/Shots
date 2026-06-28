import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuItemValidation {
    private var statusItem: NSStatusItem?
    private var getCurrentTarget: (() -> ScreenCaptureTarget?)?

    func start(getCurrentTarget: @escaping () -> ScreenCaptureTarget?) {
        self.getCurrentTarget = getCurrentTarget

        let newStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = newStatusItem

        // Force-unwrapped: NSStatusItem.button is documented to be lazily
        // created on access, so it's non-nil for a standard status item; nil
        // here would violate Apple's docs and leave the app with no UI.
        //
        // Docs: https://developer.apple.com/documentation/appkit/nsstatusitem/button
        newStatusItem.button!.image = NSImage(
            systemSymbolName: "square.and.pencil",
            accessibilityDescription: "Shots"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        if newStatusItem.button!.image == nil {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Shots can't start"
            alert.informativeText = "Your system does not support the selected icon in the menu bar. Please report this to support at support@thedeeds.net so they can fix it."
            alert.addButton(withTitle: "Quit")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let menu = NSMenu()

        let openFolderItem = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openScreenshotsFolder), keyEquivalent: "o")
        openFolderItem.keyEquivalentModifierMask = [.command]
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        newStatusItem.menu = menu
    }

    @objc private func openScreenshotsFolder() {
        guard case .directory(let url) = getCurrentTarget?() else { return }
        NSWorkspace.shared.open(url)
    }

    // Called by AppKit before every menu open — return false to disable this item.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(openScreenshotsFolder):
            guard case .directory = getCurrentTarget?() else { return false }
            return true
        default:
            return true
        }
    }
}
