import AppKit

// One reponibiilty - wiring/flow.
//
// This file will only change when the WIRING changes: who talks to whom, and
// when.
//
// If you're writing HOW something works inside the coordinator, it belongs in a
// component; the coordinator keeps only WHICH component talks to WHICH, and
// WHEN. Hold that line and it can never become a God.

@MainActor
final class AppCoordinator {
    private let statusItemController = StatusItemController()
    private var screenCaptureTargetMonitor: ScreenCaptureTargetMonitor?
    private let toastController = ToastController()
    private var currentScreenCaptureTarget: ScreenCaptureTarget?
    private var renamePanelController: RenamePanelController?
    private var previousFrontmostApplication: NSRunningApplication?
    private var detector: ScreenCaptureDetector?
    private var openMenuHotKey: GlobalHotKey?
    private var recentScreenshotHotKeys: [GlobalHotKey] = []

    func start() {
        statusItemController.start(
            getCurrentTarget: { [weak self] in self?.currentScreenCaptureTarget },
            onOpenScreenshot: { [weak self] url in
                self?.openOrSwitchTo(url: url)
            },
            onMenuWillOpen: { [weak self] in
                // The status menu opening does not reliably cause other windows
                // in the same app to resign key, so the rename panel can stay
                // open behind the menu. Explicitly tell the coordinator to
                // close it before the menu appears.
                //
                // Clear previousFrontmostApplication first so the panel's
                // onComplete doesn't restore focus to the previous app — that
                // would deactivate us and the menu would close instantly.
                self?.previousFrontmostApplication = nil
                self?.renamePanelController?.closeWithoutCancel()
                self?.renamePanelController = nil
                // Suspend recent-screenshot hotkeys so they don't collide with
                // the menu's own ⌘⌥1-9 item shortcuts while the menu is open.
                self?.suspendRecentScreenshotHotkeys()
            },
            onMenuDidClose: { [weak self] in
                self?.resumeRecentScreenshotHotkeys()
            },
            // Route toasts through the coordinator's ToastController so they
            // stack with the app's other toasts (readiness, target changes,
            // errors) instead of overlapping a separate stack.
            showToast: { [weak self] message in
                self?.toastController.show(message: message)
            }
        )

        registerHotkeys()

        let captureDetector = ScreenCaptureDetector()
        captureDetector.onNewScreenshot = { [weak self] url in
            // We never switch to a new capture while the rename panel is open.
            // Beyond avoiding interruption mid-rename, this matters for the
            // common case of screenshots taken back-to-back: keeping the first
            // one in the panel means renaming the firt one acts as a divider to
            // show the rest of shots in serieis are after his renamed file.
            // where the user can pick them in order after finishing the first.
            // Without this, each new capture would replace the panel and the
            // user would have to hunt through previews to find where their
            // series started.
            guard self?.renamePanelController == nil else { return }
            self?.openOrSwitchTo(url: url, showPreview: false)
        }
        detector = captureDetector

        do {
            let monitor = ScreenCaptureTargetMonitor()
            try monitor.start { [weak self] target in
                self?.updateCurrentScreenCaptureTargetWithToast(target)
            }
            screenCaptureTargetMonitor = monitor
        } catch {
            toastController.show(message: "Shots: Unable to detect where screenshots are being saved: \(error.localizedDescription)")
        }
    }

    private func updateCurrentScreenCaptureTargetWithToast(_ target: ScreenCaptureTarget) {
        currentScreenCaptureTarget = target

        switch target {
        case .directory(let url):
            let preposition = switch url.lastPathComponent {
                case "Desktop": "on your"
                case "Documents": "in your"
                default: "in"
            }
            toastController.show(message: "Shots: Ready for new screenshots \(preposition) \(url.lastPathComponent)")
            do {
                try detector?.startWatching(folder: url)
            } catch {
                toastController.show(message: "Shots: Unable to watch for new screenshots: \(error.localizedDescription)")
            }
        case .nonFolder(let label):
            toastController.show(message: "Shots: \(label) is not a folder. Pausing.")
            detector?.stop()
        }
    }

    // Switches to a screenshot if a panel is already showing, or creates a new one.
    // No busy check: the only way a panel can be open AND a switch triggered is via
    // ⌘⌥1-9 global hotkeys (which don't change focus). Menu clicks and ⌘⌥. always
    // close the panel first (focus loss) before the user can interact with the menu.
    // So by the time a menu click reaches openOrSwitchTo, the panel is already nil
    // and we take the create path. Auto-capture (file watcher) checks renamePanelController
    // == nil before calling this, so it never interrupts an open panel.
    func openOrSwitchTo(url: URL, showPreview: Bool = true) {
        if let panel = renamePanelController {
            panel.switchToUrl(url, showPreview: showPreview)
        } else {
            // Capture the frontmost app before activating ourselves, so we can
            // restore focus when the panel closes — like Spotlight returning you
            // to where you were. Skip when our app is already frontmost (menu
            // clicks), since there's nothing to restore to.
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousFrontmostApplication = frontApp
            }

            let panel = RenamePanelController(fileURL: url, showPreview: showPreview)
            panel.onComplete = { [weak self] in
                self?.renamePanelController = nil
                self?.restorePreviousAppFocus()
            }
            // Fire and forget: the panel closes immediately while the coordinator
            // handles trashing in the background. The panel can't close itself and
            // process the trash at the same time.
            panel.trash = { [weak self, weak panel] in
                guard let self, let panel, case .directory(let screenshotsFolder) = self.currentScreenCaptureTarget else { return }
                let fileURL = panel.fileURL
                let fileName = fileURL.lastPathComponent
                panel.dismissAfterSuccess()

                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                    } catch {
                        let rankMessage: String
                        if let screenshots = try? ScreenshotLocator.screenshotURLsSortedByCreatedAtDesc(in: screenshotsFolder),
                           let rank = screenshots.firstIndex(where: { $0 == fileURL }) {
                            rankMessage = " Hit ⌘⌥\(rank + 1) to try again."
                        } else {
                            rankMessage = ""
                        }
                        DispatchQueue.main.async {
                            self.toastController.show(message: "Could not trash \(fileName).\(rankMessage)")
                        }
                    }
                }
            }
            panel.showPanel()
            renamePanelController = panel
        }
    }

    private func restorePreviousAppFocus() {
        // defer runs when the function exits — no matter which return we take.
        // We always clear the captured app so it's single-use: it must match
        // the panel that captured it, not leak into a future close.
        defer { previousFrontmostApplication = nil }

        guard let app = previousFrontmostApplication, !app.isTerminated else {
            return
        }

        // NSRunningApplication.activate() is deprecated in macOS 14 but remains the
        // reliable way to hand focus to another app. Its replacement,
        // yieldActivation(to:), depends on the current app's activation semantics
        // and doesn't work reliably for LSUIElement (menu-bar-only) apps.
        app.activate()
    }

    // MARK: - Hotkeys

    private func registerHotkeys() {
        openMenuHotKey = GlobalHotKey(
            keyCode: GlobalHotKey.KeyCode.period,
            modifiers: GlobalHotKey.Modifiers.commandOption
        ) { [weak self] in
            self?.statusItemController.openMenu()
        }

        registerRecentScreenshotHotkeys()
    }

    private func registerRecentScreenshotHotkeys() {
        recentScreenshotHotKeys = GlobalHotKey.KeyCode.digits.enumerated().map { index, keyCode in
            GlobalHotKey(keyCode: keyCode, modifiers: GlobalHotKey.Modifiers.commandOption) { [weak self] in
                self?.openOrSwitchToRecentScreenshot(rank: index + 1)
            }
        }
    }

    private func openOrSwitchToRecentScreenshot(rank: Int) {
        guard case .directory(let url) = currentScreenCaptureTarget else {
            toastController.show(message: "Shots: Screenshots are not being saved to a folder.")
            return
        }

        guard let screenshots = try? ScreenshotLocator.screenshotURLsSortedByCreatedAtDesc(in: url) else {
            toastController.show(message: "Shots: Could not search for screenshots.")
            return
        }

        let index = rank - 1
        guard index < screenshots.count else {
            toastController.show(message: "Shots: No screenshot #\(rank) available in \(url.lastPathComponent).")
            return
        }

        openOrSwitchTo(url: screenshots[index], showPreview: true)
    }

    private func suspendRecentScreenshotHotkeys() {
        recentScreenshotHotKeys = []
    }

    private func resumeRecentScreenshotHotkeys() {
        registerRecentScreenshotHotkeys()
    }
}
