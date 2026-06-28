import AppKit

// One reponibiilty - wiring/flow.
//
// This file will only change when the WIRING changes: who talks to whom, and
// when.
//
// If you're writing HOW something works inside the coordinator, it belongs in a
// component; the coordinator keeps only WHICH component talks to WHICH, and
// WHEN. Hold that line and it can never become a God.
//
// Its single job is to compose the components (status item, watcher/detector,
// panel, renamer, trash, toasts, ...) and route events between them - who talks
// to whom, and when.
//
// It holds NO feature logic on purpose. If you're writing HOW something works
// here (a retry, a query, a validation), move it into the component that owns
// that concern. Keeping logic out of this file is what stops it from becoming a
// God object - one responsibility (wiring), not many.

@MainActor
final class AppCoordinator {
    private let statusItemController = StatusItemController()
    private var screenCaptureTargetMonitor: ScreenCaptureTargetMonitor?
    private let toastController = ToastController()
    private var currentScreenCaptureTarget: ScreenCaptureTarget?

    func start() {
        statusItemController.start()

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
            // If Desktop i want to ay "on your" if "Documents" i want to say "in your", else "in".
            let preposition = switch url.lastPathComponent {
                case "Desktop": "on your"
                case "Documents": "in your"
                default: "in"
            }
            toastController.show(message: "Shots: Ready for new screenshots \(preposition) \(url.lastPathComponent)")
        case .nonFolder(let label):
            toastController.show(message: "Shots: \(label) is not a folder. Pausing.")
        }
    }
}
