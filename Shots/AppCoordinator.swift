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

    func start() {
        statusItemController.start()
    }
}