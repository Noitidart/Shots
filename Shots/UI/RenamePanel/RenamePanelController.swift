import AppKit
import ImageIO

private final class FloatingRenamePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class RenamePanelController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    var onComplete: (() -> Void)?

    private enum Layout {
        static let defaultPanelSize = CGSize(width: 780, height: 106)
    }

    private var fileURL: URL
    private let textField: NSTextField
    private let helperLabel: NSTextField
    private let iconView: NSImageView
    private let inputEffectView: NSVisualEffectView
    private let previewImageView: NSImageView?
    private let previewDisplaySize: CGSize?
    private let idleHelperText = "Press Enter to copy path, optionally rename first. Press Esc to cancel"
    private let conflictHelperText = "This name already exists, choose a new name, or press Enter again to auto-suffix"
    private var allowsFocusLossDismissal = true
    private var isBusy = false

    init(fileURL: URL, showPreview: Bool = false) {
        self.fileURL = fileURL
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        textField = NSTextField(string: baseName)
        helperLabel = NSTextField(labelWithString: idleHelperText)
        iconView = NSImageView(
            image: NSImage(
                systemSymbolName: "square.and.pencil",
                accessibilityDescription: "Rename"
            ) ?? NSImage()
        )
        inputEffectView = NSVisualEffectView()

        // Preview is shown when showPreview is true. The image, its display size,
        // and the panel size are all derived from fileURL — the panel figures out
        // everything itself. No external sizing parameters needed.
        // Docs (CGImageSource): https://developer.apple.com/documentation/imageio/cgimagesource
        if showPreview, let pixelSize = RenamePanelController.imagePixelSize(for: fileURL) {
            let screenSize = RenamePanelController.screenWithMouse()
            let fittedSize = RenamePanelController.fittedPreviewSize(
                imagePixelSize: pixelSize,
                maxPreviewWidth: (screenSize?.visibleFrame.width ?? 1440) - 84,
                maxPreviewHeight: (screenSize?.visibleFrame.height ?? 900) - 220
            )
            let imageView = NSImageView()
            imageView.image = NSImage(contentsOf: fileURL)
            imageView.imageAlignment = .alignCenter
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 20
            imageView.layer?.masksToBounds = true
            previewImageView = imageView
            previewDisplaySize = fittedSize
        } else {
            previewImageView = nil
            previewDisplaySize = nil
        }

        let panelSize: CGSize
        if let previewDisplaySize {
            panelSize = CGSize(
                width: max(Layout.defaultPanelSize.width, previewDisplaySize.width + 84),
                height: Layout.defaultPanelSize.height + previewDisplaySize.height + 32
            )
        } else {
            panelSize = Layout.defaultPanelSize
        }

        let panel = FloatingRenamePanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .utilityWindow

        super.init(window: panel)

        let rootView = NSView(frame: panel.contentView?.bounds ?? .zero)
        rootView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = rootView
        panel.delegate = self

        let shadowContainer = NSView()
        shadowContainer.translatesAutoresizingMaskIntoConstraints = false
        shadowContainer.wantsLayer = true
        shadowContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.12).cgColor
        shadowContainer.layer?.shadowOpacity = 1
        shadowContainer.layer?.shadowRadius = 4
        shadowContainer.layer?.shadowOffset = CGSize(width: 0, height: 1)

        inputEffectView.translatesAutoresizingMaskIntoConstraints = false
        inputEffectView.material = .hudWindow
        inputEffectView.blendingMode = .behindWindow
        inputEffectView.state = .active
        inputEffectView.wantsLayer = true
        inputEffectView.layer?.cornerRadius = previewImageView == nil ? 44 : 30
        inputEffectView.layer?.masksToBounds = true
        inputEffectView.layer?.borderWidth = 1
        inputEffectView.layer?.borderColor = NSColor.black.withAlphaComponent(0.18).cgColor
        inputEffectView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        iconView.contentTintColor = .secondaryLabelColor

        textField.font = .systemFont(ofSize: 34, weight: .regular)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.textColor = .labelColor
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false

        helperLabel.textColor = .secondaryLabelColor
        helperLabel.font = .systemFont(ofSize: 11)
        helperLabel.alignment = .center
        helperLabel.lineBreakMode = .byTruncatingTail
        helperLabel.translatesAutoresizingMaskIntoConstraints = false

        shadowContainer.addSubview(inputEffectView)
        inputEffectView.addSubview(iconView)
        inputEffectView.addSubview(textField)
        inputEffectView.addSubview(helperLabel)
        if let previewImageView {
            inputEffectView.addSubview(previewImageView)
        }
        rootView.addSubview(shadowContainer)

        var constraints = [
            shadowContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 18),
            shadowContainer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -18),
            shadowContainer.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 8),
            shadowContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -10),

            inputEffectView.leadingAnchor.constraint(equalTo: shadowContainer.leadingAnchor),
            inputEffectView.trailingAnchor.constraint(equalTo: shadowContainer.trailingAnchor),
            inputEffectView.topAnchor.constraint(equalTo: shadowContainer.topAnchor),
            inputEffectView.bottomAnchor.constraint(equalTo: shadowContainer.bottomAnchor),

            iconView.leadingAnchor.constraint(equalTo: inputEffectView.leadingAnchor, constant: 28),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),

            textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 18),
            textField.trailingAnchor.constraint(equalTo: inputEffectView.trailingAnchor, constant: -32),

            helperLabel.centerXAnchor.constraint(equalTo: inputEffectView.centerXAnchor),
            helperLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 560)
        ]

        if let previewImageView, let previewDisplaySize {
            constraints += [
                textField.topAnchor.constraint(equalTo: inputEffectView.topAnchor, constant: 18),
                iconView.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
                helperLabel.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 4),
                previewImageView.topAnchor.constraint(equalTo: helperLabel.bottomAnchor, constant: 14),
                previewImageView.centerXAnchor.constraint(equalTo: inputEffectView.centerXAnchor),
                previewImageView.widthAnchor.constraint(equalToConstant: previewDisplaySize.width),
                previewImageView.heightAnchor.constraint(equalToConstant: previewDisplaySize.height),
                previewImageView.bottomAnchor.constraint(equalTo: inputEffectView.bottomAnchor, constant: -20)
            ]
        } else {
            constraints += [
                iconView.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
                textField.centerYAnchor.constraint(equalTo: inputEffectView.centerYAnchor, constant: -8),
                helperLabel.bottomAnchor.constraint(equalTo: inputEffectView.bottomAnchor, constant: -10)
            ]
        }

        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showPanel() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)

        if let window {
            let screen = RenamePanelController.screenWithMouse()
            if let screen {
                let visibleFrame = screen.visibleFrame
                let origin = CGPoint(
                    x: visibleFrame.midX - window.frame.width / 2,
                    y: visibleFrame.midY - window.frame.height / 2
                )
                window.setFrameOrigin(origin)
            } else {
                window.center()
            }
            window.makeKeyAndOrderFront(nil)
        }

        selectAllText()
    }

    func switchToUrl(_ url: URL, showPreview: Bool = true) {
        fileURL = url
        textField.stringValue = fileURL.deletingPathExtension().lastPathComponent
        isBusy = false
        textField.isEnabled = true
        helperLabel.stringValue = idleHelperText
        helperLabel.textColor = .secondaryLabelColor
        allowsFocusLossDismissal = true
        selectAllText()

        // TODO: swap preview image when showPreview is true and preview system is wired
    }

    func setBusy(_ isBusy: Bool) {
        self.isBusy = isBusy
        textField.isEnabled = !isBusy
        helperLabel.stringValue = isBusy ? "Trying to rename…" : idleHelperText
        helperLabel.textColor = .secondaryLabelColor
    }

    func showNameConflict() {
        isBusy = false
        textField.isEnabled = true
        helperLabel.stringValue = conflictHelperText
        helperLabel.textColor = .systemRed
        shakeInput()
        focusTextFieldAtEnd()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.focusTextFieldAtEnd()
        }
    }

    func selectAllText() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self.textField)
            if let editor = window.fieldEditor(true, for: self.textField) as? NSTextView {
                editor.string = self.textField.stringValue
                editor.selectedRange = NSRange(location: 0, length: self.textField.stringValue.count)
            }
        }
    }

    func dismissAfterSuccess() {
        allowsFocusLossDismissal = false
        close()
    }

    func closeWithoutCancel() {
        allowsFocusLossDismissal = false
        close()
    }

    // MARK: - Rename Flow

    private func handleSubmit() {
        let proposedName = textField.stringValue
        let originalName = fileURL.deletingPathExtension().lastPathComponent

        if proposedName == originalName {
            // Same name — no rename needed, just copy the path.
            // TODO: copy fileURL.path to clipboard (inline method, later commit)
        } else {
            // Different name — rename needed.
            // TODO: wire to FileSystem.renameSafely (next commit)
        }

        dismissAfterSuccess()
    }

    // MARK: - Window Delegate

    func windowWillClose(_ notification: Notification) {
        onComplete?()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard allowsFocusLossDismissal, !isBusy else { return }
        close()
    }

    func windowDidResignMain(_ notification: Notification) {
        guard allowsFocusLossDismissal, !isBusy else { return }
        close()
    }

    // MARK: - Text Field Delegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            handleSubmit()
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            window?.close()
            return true
        }

        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        guard !isBusy else { return }

        if helperLabel.stringValue != idleHelperText {
            helperLabel.stringValue = idleHelperText
            helperLabel.textColor = .secondaryLabelColor
        }
    }

    // MARK: - Private

    private func focusTextFieldAtEnd() {
        guard let window = window else { return }

        window.makeFirstResponder(textField)

        if let editor = window.fieldEditor(true, for: textField) as? NSTextView {
            editor.string = textField.stringValue
            editor.selectedRange = NSRange(location: textField.stringValue.count, length: 0)
        }
    }

    private func shakeInput() {
        guard let layer = inputEffectView.layer else { return }

        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, -10, 10, -7, 7, -4, 4, 0]
        animation.duration = 0.32
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "shake")
    }

    // MARK: - Image Sizing (static helpers)

    private static func imagePixelSize(for url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let h = props[kCGImagePropertyPixelHeight] as? NSNumber else {
            // Fallback: decode the image to get its size
            return NSImage(contentsOf: url)?.size
        }
        return CGSize(width: w.doubleValue, height: h.doubleValue)
    }

    private static func fittedPreviewSize(imagePixelSize: CGSize, maxPreviewWidth: CGFloat, maxPreviewHeight: CGFloat) -> CGSize {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else {
            return CGSize(width: maxPreviewWidth, height: maxPreviewHeight)
        }
        let scale = min(1, maxPreviewWidth / imagePixelSize.width, maxPreviewHeight / imagePixelSize.height)
        return CGSize(width: imagePixelSize.width * scale, height: imagePixelSize.height * scale)
    }

    private static func screenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
