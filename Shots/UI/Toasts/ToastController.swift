import AppKit

// MARK: - Panel

private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Controller

@MainActor
final class ToastController {
    private var activeToasts: [ToastWindowController] = []

    func show(message: String, duration: TimeInterval = 7) {
        let screen = activeToasts.first?.screen ?? targetScreen()
        let toast = ToastWindowController(message: message, screen: screen, duration: duration) { [weak self] toast in
            self?.removeToast(toast)
        }

        activeToasts.append(toast)
        repositionToasts(animated: false)
        toast.present()
    }

    private func removeToast(_ toast: ToastWindowController) {
        activeToasts.removeAll { $0 === toast }
        repositionToasts(animated: true)
    }

    private func repositionToasts(animated: Bool) {
        var topInset: CGFloat = 72

        for toast in activeToasts {
            topInset = toast.updatePosition(topInset: topInset, animated: animated)
        }
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
    }
}

// MARK: - Window Controller

@MainActor
private final class ToastWindowController: NSWindowController {
    private enum Layout {
        static let minWidth: CGFloat = 180
        static let height: CGFloat = 48
        static let stackSpacing: CGFloat = 8
        static let screenMargin: CGFloat = 120
        static let maxWidth: CGFloat = 900
        static let shadowHorizontalInset: CGFloat = 8
        static let messageHorizontalInset: CGFloat = 22
    }

    fileprivate let screen: NSScreen?
    private let messageLabel = NSTextField(labelWithString: "")
    private let onDismiss: (ToastWindowController) -> Void
    private let duration: TimeInterval
    private var dismissWorkItem: DispatchWorkItem?
    private var isDismissing = false

    init(message: String, screen: NSScreen?, duration: TimeInterval, onDismiss: @escaping (ToastWindowController) -> Void) {
        self.screen = screen
        self.onDismiss = onDismiss
        self.duration = duration

        let panel = ToastPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 48),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.alphaValue = 0

        super.init(window: panel)

        messageLabel.stringValue = message

        let rootView = NSView(frame: panel.contentView?.bounds ?? .zero)
        rootView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = rootView

        let shadowContainer = NSView()
        shadowContainer.translatesAutoresizingMaskIntoConstraints = false
        shadowContainer.wantsLayer = true
        shadowContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.12).cgColor
        shadowContainer.layer?.shadowOpacity = 1
        shadowContainer.layer?.shadowRadius = 4
        shadowContainer.layer?.shadowOffset = CGSize(width: 0, height: 1)

        let effectView = NSVisualEffectView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 20
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 1
        effectView.layer?.borderColor = NSColor.black.withAlphaComponent(0.16).cgColor
        effectView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .systemFont(ofSize: 14, weight: .medium)
        messageLabel.textColor = .labelColor
        messageLabel.alignment = .center
        messageLabel.lineBreakMode = .byTruncatingTail

        shadowContainer.addSubview(effectView)
        effectView.addSubview(messageLabel)
        rootView.addSubview(shadowContainer)

        NSLayoutConstraint.activate([
            shadowContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 8),
            shadowContainer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -8),
            shadowContainer.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 4),
            shadowContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -6),

            effectView.leadingAnchor.constraint(equalTo: shadowContainer.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: shadowContainer.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: shadowContainer.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: shadowContainer.bottomAnchor),

            messageLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 22),
            messageLabel.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -22),
            messageLabel.centerYAnchor.constraint(equalTo: effectView.centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        dismissWorkItem?.cancel()
        guard let window else { return }

        let finalFrame = window.frame
        window.setFrame(finalFrame, display: false)
        window.alphaValue = 0
        messageLabel.alphaValue = 1
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1
        }

        let dismissWorkItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        self.dismissWorkItem = dismissWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: dismissWorkItem)
    }

    @discardableResult
    func updatePosition(topInset: CGFloat, animated: Bool) -> CGFloat {
        guard let window, let screen else { return topInset }

        let frame = preferredFrame(topInset: topInset, on: screen)
        window.setFrame(frame, display: true, animate: window.isVisible && animated)
        return topInset + Layout.height + Layout.stackSpacing
    }

    private func preferredFrame(topInset: CGFloat, on screen: NSScreen) -> NSRect {
        let labelWidth = measuredToastWidth(on: screen)
        return NSRect(
            x: screen.frame.midX - labelWidth / 2,
            y: screen.visibleFrame.maxY - topInset - Layout.height,
            width: labelWidth,
            height: Layout.height
        )
    }

    private func measuredToastWidth(on screen: NSScreen) -> CGFloat {
        let font = messageLabel.font ?? .systemFont(ofSize: 14, weight: .medium)
        let textWidth = ceil((messageLabel.stringValue as NSString).size(withAttributes: [.font: font]).width)
        let padding = (Layout.shadowHorizontalInset + Layout.messageHorizontalInset) * 2
        let maximumWidth = min(Layout.maxWidth, screen.frame.width - Layout.screenMargin)
        return min(max(textWidth + padding, Layout.minWidth), maximumWidth)
    }

    private func dismiss() {
        guard let window, window.isVisible, !isDismissing else { return }
        isDismissing = true

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            window.animator().alphaValue = 0
        }) {
            window.orderOut(nil)
            self.onDismiss(self)
        }
    }
}
