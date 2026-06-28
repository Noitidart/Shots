import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuItemValidation, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var getCurrentTarget: (() -> ScreenCaptureTarget?)?
    private var onOpenScreenshot: ((URL) -> Void)?
    private var onMenuWillOpen: (() -> Void)?
    private var onMenuDidClose: (() -> Void)?
    private var showToast: ((String) -> Void)?

    func start(
        getCurrentTarget: @escaping () -> ScreenCaptureTarget?,
        onOpenScreenshot: @escaping (URL) -> Void,
        onMenuWillOpen: @escaping () -> Void,
        onMenuDidClose: @escaping () -> Void,
        showToast: @escaping (String) -> Void
    ) {
        self.getCurrentTarget = getCurrentTarget
        self.onOpenScreenshot = onOpenScreenshot
        self.onMenuWillOpen = onMenuWillOpen
        self.onMenuDidClose = onMenuDidClose
        self.showToast = showToast

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
        menu.delegate = self

        // MARK: - Preferences related menu items

        let quotePathsItem = NSMenuItem(title: "Quote Copied Paths (CLI Friendly)", action: #selector(toggleQuotePaths(_:)), keyEquivalent: "")
        quotePathsItem.target = self
        quotePathsItem.state = AppPreferences.wrapCopiedPathsInSingleQuotes ? .on : .off
        menu.addItem(quotePathsItem)

        menu.addItem(.separator())

        // MARK: - Folder related menu items

        let openFolderItem = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openScreenshotsFolder), keyEquivalent: "o")
        openFolderItem.keyEquivalentModifierMask = [.command]
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        // Ordered safest-first: ⌘T is permanently bound to the safest scope (14+ days).
        // If a safer scope is ever added, the shortcut must move to it.
        let trashTwoWeeks = NSMenuItem(title: "Trash Very Old Screenshots (14+ days)", action: #selector(trashScreenshotsWithToast(_:)), keyEquivalent: "t")
        menu.addItem(trashTwoWeeks)
        trashTwoWeeks.keyEquivalentModifierMask = [.command]
        trashTwoWeeks.target = self
        trashTwoWeeks.representedObject = ScreenshotTrashScope.old(minimumAgeInHours: 336, ageDescription: "14 days")

        let trashOneDay = NSMenuItem(title: "Trash Old Screenshots (24+ hours)", action: #selector(trashScreenshotsWithToast(_:)), keyEquivalent: "")
        menu.addItem(trashOneDay)
        trashOneDay.target = self
        trashOneDay.representedObject = ScreenshotTrashScope.old(minimumAgeInHours: 24, ageDescription: "24 hours")

        let trashAll = NSMenuItem(title: "Trash All Screenshots", action: #selector(trashScreenshotsWithToast(_:)), keyEquivalent: "")
        menu.addItem(trashAll)
        trashAll.target = self
        trashAll.representedObject = ScreenshotTrashScope.all

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        newStatusItem.menu = menu
    }

    // MARK: - Actions

    func openMenu() {
        statusItem?.button?.performClick(nil)
    }

    @objc private func openScreenshotsFolder() {
        guard case .directory(let url) = getCurrentTarget?() else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openRecentScreenshot(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onOpenScreenshot?(url)
    }

    @objc private func trashScreenshotsWithToast(_ sender: NSMenuItem) {
        guard let scope = sender.representedObject as? ScreenshotTrashScope else {
            fatalError("dev-error: scope was nil or wrong type, but menu items always set it to a ScreenshotTrashScope at creation so dev set wrong representedObject")
        }

        guard case .directory(let url) = getCurrentTarget?() else {
            fatalError("dev-error: target is not a folder, but validateMenuItem disables trash items when it isn't so this should have never got called")
        }

        let folderName = url.lastPathComponent

        ScreenshotTrasher.trashScreenshots(in: url, scope: scope) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(0):
                self.showToast?("Shots: \(scope.emptyMessage(in: folderName))")
            case .success(let count):
                self.showToast?("Shots: \(scope.successMessage(count: count, in: folderName))")
            case .failure(let error):
                self.showToast?("Shots: \(error.localizedDescription)")
            }
        }
    }

    @objc private func toggleQuotePaths(_ sender: NSMenuItem) {
        let newValue = sender.state != .on
        AppPreferences.wrapCopiedPathsInSingleQuotes = newValue
        sender.state = newValue ? .on : .off
    }

    // MARK: - Menu Validation

    // Called by AppKit before every menu open — return false to disable this item.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(openScreenshotsFolder), #selector(trashScreenshotsWithToast(_:)):
            guard case .directory = getCurrentTarget?() else { return false }
            return true
        default:
            return true
        }
    }

    // MARK: - Menu Delegate

    func menuWillOpen(_ menu: NSMenu) {
        onMenuWillOpen?()
    }

    func menuDidClose(_ menu: NSMenu) {
        onMenuDidClose?()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        removeRecentSectionItems(from: menu)
        addRecentSectionItemsIfFolder(menu)
    }

    // MARK: - Recent Section

    private func removeRecentSectionItems(from menu: NSMenu) {
        menu.items
            .filter { $0.tag == RecentScreenshots.menuTag }
            .reversed()
            .forEach(menu.removeItem)
    }

    private func addRecentSectionItemsIfFolder(_ menu: NSMenu) {
        guard case .directory(let url) = getCurrentTarget?() else { return }

        // Early return on failure rather than showing "No screenshots yet"
        // (which would be misleading — the search failed, not that there are no
        // screenshots).  No dedicated error item either: mdfind is a system
        // tool that's always present on macOS, so failure essentially can't
        // happen outside of a broken OS. Building an error-state menu item for
        // an impossible case isn't worth the complexity.
        guard let screenshots = try? ScreenshotLocator.screenshotURLsSortedByCreatedAtDesc(in: url) else { return }

        let recent = Array(screenshots.prefix(RecentScreenshots.maxCount))

        if recent.isEmpty {
            let placeholder = NSMenuItem(title: "No screenshots yet", action: nil, keyEquivalent: "")
            placeholder.tag = RecentScreenshots.menuTag
            placeholder.isEnabled = false
            menu.insertItem(placeholder, at: 0)
        } else {
            for (index, url) in recent.enumerated() {
                let hotkeyNumber = index + 1
                let item = NSMenuItem(
                    title: url.lastPathComponent,
                    action: #selector(openRecentScreenshot(_:)),
                    keyEquivalent: "\(hotkeyNumber)"
                )
                item.keyEquivalentModifierMask = [.command, .option]
                item.target = self
                item.representedObject = url
                item.tag = RecentScreenshots.menuTag
                menu.insertItem(item, at: index)
            }
        }

        let separator = NSMenuItem.separator()
        separator.tag = RecentScreenshots.menuTag
        menu.insertItem(separator, at: recent.isEmpty ? 1 : recent.count)
    }
}

// MARK: - Recent Screenshots Constants

private enum RecentScreenshots {
    // Start at 1, not 0 as it is NSMenuItem's default tag, so using 0 would
    // match every standard menu item.
    static let menuTag = 1

    // Limited to 9 because menu items use ⌘⌥1 through ⌘⌥9 as key equivalents,
    // and keyEquivalent is a single character — 10+ isn't possible.
    static let maxCount = 9
}
