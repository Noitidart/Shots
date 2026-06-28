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
    private var detector: ScreenCaptureDetector?

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
                self?.renamePanelController?.closeWithoutCancel()
                self?.renamePanelController = nil
            }
        )

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
            let panel = RenamePanelController(fileURL: url, showPreview: showPreview)
            panel.onComplete = { [weak self] in
                self?.renamePanelController = nil
            }
            panel.showPanel()
            renamePanelController = panel
        }
    }
}
