import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuItemValidation, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var getCurrentTarget: (() -> ScreenCaptureTarget?)?
    private var onOpenScreenshot: ((URL) -> Void)?
    private var onMenuWillOpen: (() -> Void)?
    private var onMenuDidClose: (() -> Void)?
    private var showToast: ((String) -> Void)?
    private var helpViewController: HelpViewController?

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

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = LaunchAtLoginController.isEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        // MARK: - Folder related menu items

        let openFolderItem = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openScreenshotsFolder), keyEquivalent: "o")
        openFolderItem.keyEquivalentModifierMask = [.command]
        openFolderItem.target = self
        openFolderItem.tag = MenuTags.folderRelated
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

        let helpItem = NSMenuItem(title: "Help", action: #selector(showHelp), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
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

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newValue = sender.state != .on
        let success = newValue ? LaunchAtLoginController.enable() : LaunchAtLoginController.disable()

        if success {
            sender.state = newValue ? .on : .off
        } else {
            showToast?("Shots: Could not change launch at login. Check System Settings → General → Login Items.")
        }
    }

    @objc private func showHelp() {
        if helpViewController == nil {
            helpViewController = HelpViewController()
        }
        helpViewController?.showHelp()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
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
        removeTargetInfoItems(from: menu)
        addRecentSectionItemsIfFolder(menu)
        addTargetInfoItems(menu)
    }

    // MARK: - Recent Section

    private func removeRecentSectionItems(from menu: NSMenu) {
        menu.items
            .filter { $0.tag == MenuTags.recentScreenshots }
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

        let recent = Array(screenshots.prefix(9))

        if recent.isEmpty {
            let placeholder = NSMenuItem(title: "No screenshots yet", action: nil, keyEquivalent: "")
            placeholder.tag = MenuTags.recentScreenshots
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
                item.tag = MenuTags.recentScreenshots
                menu.insertItem(item, at: index)
            }
        }

        let separator = NSMenuItem.separator()
        separator.tag = MenuTags.recentScreenshots
        menu.insertItem(separator, at: recent.isEmpty ? 1 : recent.count)
    }

    // MARK: - Target Info Section

    // Folder mode: the folder name sits near the folder-dependent actions it describes.
    // Non-folder mode: the target label and an explanatory note move to the top so the
    // user sees the incompatibility before reaching the disabled actions below.
    private func removeTargetInfoItems(from menu: NSMenu) {
        menu.items
            .filter { $0.tag == MenuTags.targetInfo }
            .reversed()
            .forEach(menu.removeItem)
    }

    private func addTargetInfoItems(_ menu: NSMenu) {
        guard let target = getCurrentTarget?() else { return }

        switch target {
        case .directory(let url):
            let headerItem = NSMenuItem()
            headerItem.view = StatusMenuHeaderView(text: url.lastPathComponent)
            headerItem.tag = MenuTags.targetInfo
            headerItem.isEnabled = false

            if let firstFolderRelatedIndex = menu.items.firstIndex(where: { $0.tag == MenuTags.folderRelated }) {
                menu.insertItem(headerItem, at: firstFolderRelatedIndex)
            }

        case .nonFolder(let label):
            let headerItem = NSMenuItem()
            headerItem.view = StatusMenuHeaderView(text: "Screenshot Target: \(label)")
            headerItem.tag = MenuTags.targetInfo
            headerItem.isEnabled = false
            menu.insertItem(headerItem, at: 0)

            let noteItem = NSMenuItem()
            noteItem.view = StatusMenuNoteView(text: "Use ⌘⇧5 → Options → Pick a folder.")
            noteItem.tag = MenuTags.targetInfo
            noteItem.isEnabled = false
            menu.insertItem(noteItem, at: 1)

            let separator = NSMenuItem.separator()
            separator.tag = MenuTags.targetInfo
            menu.insertItem(separator, at: 2)
        }
    }
}

// MARK: - Menu Constants

private enum MenuTags {
    // Start at 1, not 0 as it is NSMenuItem's default tag, so using 0 would
    // match every standard menu item.
    static let recentScreenshots = 1
    static let targetInfo = 2

    static let folderRelated = 3
}
