import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenuForEditCommands()

        coordinator.start()
    }
    
    // LSUIElement apps still need a real app main menu for AppKit to route
    // standard Edit commands to the focused editor. Without this, when the
    // rename panel's text field is focused, shortcuts like ⌘A/⌘X/⌘C/⌘V/⌘Z do
    // not reach its field editor naturally. The menu is invisible; the user
    // never sees it. 
    private func installMainMenuForEditCommands() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")

        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)

        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")

    }
}
