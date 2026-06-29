import AppKit

@MainActor
final class HelpViewController: NSWindowController {
    init() {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textStorage?.setAttributedString(Self.helpText)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Shots Help"
        window.contentView = scrollView
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func showHelp() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Help Text

    private static let helpText: NSAttributedString = {
        let result = NSMutableAttributedString()

        let bodyFont = NSFont.systemFont(ofSize: 13)
        let bodyColor = NSColor.labelColor
        let shortcutFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let shortcutColor = NSColor.secondaryLabelColor

        let shortcutPara = NSMutableParagraphStyle()
        shortcutPara.tabStops = [NSTextTab(textAlignment: .left, location: 60, options: [:])]

        func header(_ text: String) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 14),
                .foregroundColor: bodyColor,
            ]
            result.append(NSAttributedString(string: text + "\n\n", attributes: attrs))
        }

        func body(_ text: String) {
            result.append(NSAttributedString(string: text + "\n\n", attributes: [
                .font: bodyFont, .foregroundColor: bodyColor,
            ]))
        }

        func shortcut(_ keys: String, _ description: String) {
            result.append(NSAttributedString(string: keys, attributes: [
                .font: shortcutFont, .foregroundColor: shortcutColor,
                .paragraphStyle: shortcutPara,
            ]))
            result.append(NSAttributedString(string: "\t" + description + "\n", attributes: [
                .font: bodyFont, .foregroundColor: bodyColor,
                .paragraphStyle: shortcutPara,
            ]))
        }

        func spacer() {
            result.append(NSAttributedString(string: "\n"))
        }

        header("Global Hotkeys")
        body("These work from any application — you don't need to switch to Shots first.")
        shortcut("⌘⌥.", "Open the Shots menu")
        shortcut("⌘⌥1-9", "Rename the 1st-9th most recent screenshot")

        spacer()

        header("Rename Panel")
        body("When you take a screenshot, the rename panel appears automatically with the filename selected. Type a new name and press Enter to rename and copy the path. Press Esc to cancel.")
        body("A preview thumbnail is shown only when you open a recent screenshot via the ⌘⌥1-9 hotkeys or from the menu. When a brand-new capture auto-opens the panel, no preview is shown.")

        spacer()

        header("Menu Shortcuts")
        shortcut("⌘O", "Open the screenshots folder")
        shortcut("⌘T", "Trash screenshots older than 14 days")
        shortcut("⌘Q", "Quit Shots")

        spacer()

        header("Screenshot Destination")
        body("Where screenshots are saved is controlled by macOS, not Shots. Use ⌘⇧5 → Options to change the destination.")

        spacer()

        header("Non-Folder Mode")
        body("When the destination is set to Clipboard or another non-folder mode, rename, trash, and folder actions are paused. The menu shows the current target and a note explaining how to switch back.")

        return result
    }()
}
