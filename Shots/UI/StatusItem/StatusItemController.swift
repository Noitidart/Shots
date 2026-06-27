import AppKit

@MainActor
final class StatusItemController {
    private var statusItem: NSStatusItem?
    
    func start() {
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
            // The selected icon is not supported. Quit.
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
    }
}
