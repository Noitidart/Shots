import AppKit
import ImageIO

private final class FloatingRenamePanel: NSPanel {
    var onModifiedReturn: ((NSEvent.ModifierFlags) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control])
        guard event.type == .keyDown,
              event.keyCode == 36,
              modifiers == .command || modifiers == .control else {
            return super.performKeyEquivalent(with: event)
        }

        if onModifiedReturn?(event.modifierFlags) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

// Preview image view that initiates a cross-application drag of the screenshot
// file when the user drags it. Hides the panel for the duration of the drag so
// it doesn't block the drop target, then either restores it (cancelled/missed)
// or closes it (successful drop) via the controller callbacks.
private final class DraggablePreviewImageView: NSImageView, NSDraggingSource {
    var fileURL: URL?
    var onDragWillBegin: (() -> Void)?
    var onDragEnded: ((NSDragOperation, NSPoint) -> Void)?

    private var mouseDownLocation = CGPoint.zero
    // Latched true once a drag session has begun for the current mouse-down, and
    // cleared only on the next mouseDown. Clearing it here (not on drag-end) is
    // what stops a cancelled drag from re-triggering: after Esc cancels mid-drag
    // the button is usually still held, so mouseDragged keeps firing.
    private var hasStartedDragForCurrentMouseDown = false
    private static let dragThreshold: CGFloat = 4

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        hasStartedDragForCurrentMouseDown = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !hasStartedDragForCurrentMouseDown, let url = fileURL, let image = image else { return }

        let dx = event.locationInWindow.x - mouseDownLocation.x
        let dy = event.locationInWindow.y - mouseDownLocation.y
        guard (dx * dx + dy * dy).squareRoot() >= Self.dragThreshold else { return }

        let item = NSDraggingItem(pasteboardWriter: ScreenshotDragWriter(url: url, image: image))
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
        hasStartedDragForCurrentMouseDown = true
    }

    // MARK: - NSDraggingSource

    // Each destination picks the operation it wants from this set: Finder folders
    // take .move (Finder relocates the file itself), browsers and chat apps take
    // .copy (attach / read bytes), and the Dock Trash takes .delete. Note .delete
    // does NOT trash the file for us — the Trash expects the source to delete its
    // own data, so we trash it ourselves; see the .delete branch in
    // handleDragEnded. Only the Trash requests .delete, so allowing it can't cause
    // deletions anywhere else.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.move, .copy, .delete]
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDragWillBegin?()
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // Don't clear hasStartedDragForCurrentMouseDown here — that latch is what
        // keeps a cancelled drag from re-triggering on continued mouse movement.
        // It clears on the next mouseDown instead. screenPoint is forwarded so
        // the controller can focus the app that received the drop.
        onDragEnded?(operation, screenPoint)
    }
}

// Provides the screenshot as several pasteboard flavors for a single dragged
// item. Destinations inspect the *advertised* type list during the hover phase
// (draggingEntered) before reading any data, so the set must cover every flavor
// a target might key off:
// - .fileURL (public.file-url): Finder, Trash, Dock folders.
// - NSFilenamesPboardType: legacy array-of-paths that Chromium/Safari read for
//   <input type=file> and attachment drop zones (Gmail, GitHub).
// - .url (public.url): generic URL checkers (some Dock/app targets).
// - .png / .tiff: image bytes for chat apps and image-aware drop targets that
//   only highlight when they see an image flavor.
private final class ScreenshotDragWriter: NSObject, NSPasteboardWriting {
    private let url: URL
    private let image: NSImage

    init(url: URL, image: NSImage) {
        self.url = url
        self.image = image
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL, Self.filenamesPboardType, Self.urlPboardType, .png, .tiff]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL, Self.urlPboardType:
            url.absoluteString
        case Self.filenamesPboardType:
            [url.path]
        case .png:
            // Raw file bytes — macOS screenshots are PNG, so this is exact.
            try? Data(contentsOf: url)
        case .tiff:
            image.tiffRepresentation
        default:
            nil
        }
    }

    private static let filenamesPboardType = NSPasteboard.PasteboardType(rawValue: "NSFilenamesPboardType")
    private static let urlPboardType = NSPasteboard.PasteboardType(rawValue: "public.url")
}

@MainActor
final class RenamePanelController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    var onComplete: (() -> Void)?
    var trash: ((URL) -> Void)?

    private enum Layout {
        static let defaultPanelSize = CGSize(width: 780, height: 106)
    }

    private var fileURL: URL
    private let textField: NSTextField
    private let helperLabel: NSTextField
    private let iconView: NSImageView
    private let inputEffectView: NSVisualEffectView
    private var previewImageView: DraggablePreviewImageView?
    private var previewDisplaySize: CGSize?
    private var previewWidthConstraint: NSLayoutConstraint?
    private var previewHeightConstraint: NSLayoutConstraint?
    private let conflictHelperText = "This name already exists, choose a new name, or press Enter again to auto-suffix"

    private var idleHelperText: String {
        Self.formatHelperText()
    }

    private static func formatHelperText() -> String {
        let defaultFormat = AppPreferences.defaultCopiedPathFormat
        let cmdFormat = defaultFormat == .cliFriendly ? CopiedPathFormat.noQuotes : .cliFriendly
        let ctrlFormat = defaultFormat == .markdownCode ? CopiedPathFormat.noQuotes : .markdownCode
        return "Enter: copy \(defaultFormat.shortName) · ⌘Enter: \(cmdFormat.shortName) · ⌃Enter: \(ctrlFormat.shortName) · Esc: cancel · ⌘⌫: trash"
    }
    private let trashHintText = "Hit ⌘⌫ again to trash"
    private var allowsFocusLossDismissal = true
    // Set when the panel closes because the user successfully dragged the
    // preview onto a drop target. AppCoordinator reads it to skip restoring the
    // previous app's focus — the user just landed in their drop target (e.g. a
    // browser) and should stay there.
    private(set) var closedBySuccessfulDrag = false
    private var isBusy = false
    private var isTrashDeleteArmed = false
    private var isNextTextChangeTheOneThatShowedTrashHint = false
    private var pendingAutoSuffixBaseName: String?

    init(fileURL: URL) {
        self.fileURL = fileURL
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        textField = NSTextField(string: baseName)
        helperLabel = NSTextField(labelWithString: Self.formatHelperText())
        iconView = NSImageView(
            image: NSImage(
                systemSymbolName: "square.and.pencil",
                accessibilityDescription: "Rename"
            ) ?? NSImage()
        )
        inputEffectView = NSVisualEffectView()

        // The image, its display size, and the panel size are all derived from
        // fileURL — the panel figures out everything itself, so no external
        // sizing parameters are needed. The else branch (compact, no preview)
        // is the graceful fallback for an unreadable image.
        // Docs (CGImageSource): https://developer.apple.com/documentation/imageio/cgimagesource
        if let pixelSize = RenamePanelController.imagePixelSize(for: fileURL) {
            let screenSize = RenamePanelController.screenWithMouse()
            let fittedSize = RenamePanelController.fittedPreviewSize(
                imagePixelSize: pixelSize,
                maxPreviewWidth: (screenSize?.visibleFrame.width ?? 1440) - 84,
                maxPreviewHeight: (screenSize?.visibleFrame.height ?? 900) - 220
            )
            let imageView = DraggablePreviewImageView()
            imageView.image = NSImage(contentsOf: fileURL)
            imageView.imageAlignment = .alignCenter
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 20
            imageView.layer?.masksToBounds = true
            imageView.fileURL = fileURL
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

        // Wire the preview drag callbacks here (not during view creation) so the
        // [weak self] capture happens after super.init, when self is valid.
        previewImageView?.onDragWillBegin = { [weak self] in
            self?.handleDragWillBegin()
        }
        previewImageView?.onDragEnded = { [weak self] operation, screenPoint in
            self?.handleDragEnded(operation: operation, screenPoint: screenPoint)
        }

        panel.onModifiedReturn = { [weak self] flags in
            guard let self, self.window?.isVisible == true, !self.isBusy else { return false }
            self.handleSubmit(copyFormat: self.copyFormat(from: flags))
            return true
        }

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
            let pw = previewImageView.widthAnchor.constraint(equalToConstant: previewDisplaySize.width)
            let ph = previewImageView.heightAnchor.constraint(equalToConstant: previewDisplaySize.height)
            previewWidthConstraint = pw
            previewHeightConstraint = ph

            constraints += [
                textField.topAnchor.constraint(equalTo: inputEffectView.topAnchor, constant: 18),
                iconView.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
                helperLabel.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 4),
                previewImageView.topAnchor.constraint(equalTo: helperLabel.bottomAnchor, constant: 14),
                previewImageView.centerXAnchor.constraint(equalTo: inputEffectView.centerXAnchor),
                pw,
                ph,
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

        // Floating panels with hidesOnDeactivate=false don't reliably fire
        // windowDidResignKey when the app deactivates (e.g. Cmd+Tab). This app-level
        // notification is the reliable fallback.
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidDeactivate),
            name: NSApplication.didResignActiveNotification, object: nil
        )

        selectAllText()
    }

    func switchToUrl(_ url: URL) {
        fileURL = url
        textField.stringValue = fileURL.deletingPathExtension().lastPathComponent
        isBusy = false
        textField.isEnabled = true
        helperLabel.stringValue = idleHelperText
        helperLabel.textColor = .secondaryLabelColor
        allowsFocusLossDismissal = true
        isTrashDeleteArmed = false
        isNextTextChangeTheOneThatShowedTrashHint = false
        pendingAutoSuffixBaseName = nil
        selectAllText()

        if let previewImageView {
            updatePreview(for: url)
        }
    }

    private func updatePreview(for url: URL) {
        guard let pixelSize = Self.imagePixelSize(for: url) else { return }

        let screen = Self.screenWithMouse()
        let newFittedSize = Self.fittedPreviewSize(
            imagePixelSize: pixelSize,
            maxPreviewWidth: (screen?.visibleFrame.width ?? 1440) - 84,
            maxPreviewHeight: (screen?.visibleFrame.height ?? 900) - 220
        )

        previewDisplaySize = newFittedSize
        previewImageView?.fileURL = url
        previewImageView?.image = NSImage(contentsOf: url)
        previewWidthConstraint?.constant = newFittedSize.width
        previewHeightConstraint?.constant = newFittedSize.height

        let newPanelSize = CGSize(
            width: max(Layout.defaultPanelSize.width, newFittedSize.width + 84),
            height: Layout.defaultPanelSize.height + newFittedSize.height + 32
        )

        if let window {
            let frame = window.frame
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let newFrame = NSRect(
                x: center.x - newPanelSize.width / 2,
                y: center.y - newPanelSize.height / 2,
                width: newPanelSize.width,
                height: newPanelSize.height
            )
            window.setFrame(newFrame, display: true, animate: false)
        }
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
        // We want caret at end as likely user will add a suffix.
        restoreEditingWithCaretAtEnd()

        // Retry focusing after delay in case focus failed because the text
        // field didn't get enabled fast enough to be before the focus request.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.restoreEditingWithCaretAtEnd()
        }
    }

    // Defer selection to the next main-queue turn so AppKit has a chance to
    // finish activation and field-editor setup before we ask the text field to
    // select all.
    func selectAllText() {
        DispatchQueue.main.async { [weak self] in
            self?.textField.selectText(nil)
        }
    }

    func dismissAfterSuccess() {
        allowsFocusLossDismissal = false
        close()
    }

    // MARK: - Preview Drag

    private func handleDragWillBegin() {
        // Suppress focus-loss dismissal for the whole drag. Dropping over another
        // app deactivates us, and without this guard windowDidResignKey/
        // appDidDeactivate would close the panel before the drag-end callback can
        // restore it. The panel is hidden (alpha 0) regardless, so this costs no
        // screen space — it only stops focus loss from deciding the panel's fate
        // mid-gesture. Dismissal is re-armed in restorePanelFromDrag, or the
        // panel is closed outright in closeAfterSuccessfulDrag.
        allowsFocusLossDismissal = false
        window?.alphaValue = 0
    }

    private func handleDragEnded(operation: NSDragOperation, screenPoint: NSPoint) {
        if operation.isEmpty {
            // Cancelled (Esc) or dropped where nothing accepted it — bring it back.
            restorePanelFromDrag()
        } else if operation.contains(.delete) {
            // Trash path. Unlike .move (where the destination relocates the file),
            // .delete means the SOURCE must delete its own data — the Dock Trash
            // won't move a file owned by another app, it just signals "delete it."
            // So we trash it ourselves, reusing the ⌘⌫ path. dismissAfterSuccess
            // (not closeAfterSuccessfulDrag) restores the previous app, matching
            // ⌘⌫-to-Trash: there's no useful app to focus for a Dock drop.
            dismissAfterSuccess()
            trash?(fileURL)
        } else {
            closeAfterSuccessfulDrag()
            // Without this our app stays frontmost after closing the panel (it has
            // no window left), stranding the user away from where they just
            // dropped. Activate the app under the drop point so they land there.
            Self.activateDropTarget(at: screenPoint)
        }
    }

    private func restorePanelFromDrag() {
        window?.alphaValue = 1
        // If the failed drop was over another app, reassert ourselves so the
        // panel returns focused and ready, not stranded behind that app.
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
        // Re-arm dismissal after a beat so the activation/drop churn from the
        // just-ended drag drains first; otherwise a late resign-key/deactivate
        // could immediately close the panel we just brought back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.allowsFocusLossDismissal = true
        }
    }

    private func closeAfterSuccessfulDrag() {
        closedBySuccessfulDrag = true
        allowsFocusLossDismissal = false
        close()
    }

    func closeWithoutCancel() {
        allowsFocusLossDismissal = false
        close()
    }

    // MARK: - Rename Flow

    private func handleSubmit(copyFormat: CopiedPathFormat) {
        do {
            let proposedName = try FileSystem.validateName(textField.stringValue)
            let originalURL = fileURL
            let originalName = originalURL.deletingPathExtension().lastPathComponent

            // Same name — no rename needed, just copy the existing path.
            if proposedName == originalName {
                copyPathToClipboard(originalURL.path, format: copyFormat)
                dismissAfterSuccess()
                return
            }

            // Determine target URL. If the last submit with this same name caused a
            // conflict, auto-suffix ("name 2.png", "name 3.png"…).
            let targetURL: URL
            if pendingAutoSuffixBaseName == proposedName {
                targetURL = FileSystem.autoSuffixedURL(from: originalURL, baseName: proposedName)
                pendingAutoSuffixBaseName = nil
            } else {
                pendingAutoSuffixBaseName = nil
                targetURL = FileSystem.targetURL(from: originalURL, baseName: proposedName)
            }

            // Optimistic clipboard copy — put the new path on the clipboard before
            // renaming so the user can paste immediately. If the rename fails, the
            // clipboard is restored to the original path.
            copyPathToClipboard(targetURL.path, format: copyFormat)
            setBusy(true)

            Task { [weak self] in
                guard let self else { return }
                do {
                    try await FileSystem.renameSafely(from: originalURL, to: targetURL)
                    guard self.fileURL == originalURL else { return } // panel switched — skip
                    self.dismissAfterSuccess()
                } catch is CancellationError {
                    return
                } catch {
                    // Always restore clipboard on failure, even if the panel switched
                    // to a different file — the clipboard shouldn't keep a stale wrong path.
                    self.copyPathToClipboard(originalURL.path, format: copyFormat)

                    guard self.fileURL == originalURL else { return }
                    self.setBusy(false)

                    if case RenameFailure.destinationAlreadyExists = error {
                        self.pendingAutoSuffixBaseName = proposedName
                        self.showNameConflict()
                    } else {
                        self.selectAllText()
                        self.showError(error)
                    }
                    }
                }
            } catch {
            showError(error)
        }
    }

    private func copyPathToClipboard(_ path: String, format: CopiedPathFormat) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(format.wrap(path), forType: .string)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Rename Failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Window Delegate

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
        onComplete?()
    }

    // Fires after the window is truly key — which requires the app to be active.
    // NSApp.activate(ignoringOtherApps:) is asynchronous on macOS 14+, so the
    // selectAllText() call in showPanel() may run before activation completes,
    // causing makeFirstResponder to fail silently. This handler is the reliable
    // fallback: it fires only when the window can actually accept key focus.
    func windowDidBecomeKey(_ notification: Notification) {
        selectAllText()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard allowsFocusLossDismissal, !isBusy else { return }
        close()
    }

    func windowDidResignMain(_ notification: Notification) {
        guard allowsFocusLossDismissal, !isBusy else { return }
        close()
    }

    @objc private func appDidDeactivate() {
        guard allowsFocusLossDismissal, !isBusy else { return }
        close()
    }

    // MARK: - Text Field Delegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector != #selector(NSResponder.deleteToBeginningOfLine(_:)) {
            clearTrashDeleteState()
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            window?.close()
            return true
        }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            handleSubmit(copyFormat: copyFormat(from: []))
            return true
        }

        if commandSelector == #selector(NSResponder.deleteToBeginningOfLine(_:)) {
            if isTrashDeleteArmed || textField.stringValue.isEmpty || isAllTextSelected(in: textView) || isCaretAtStart(in: textView) {
                clearTrashDeleteState()
                dismissAfterSuccess()
                trash?(fileURL)
                return true
            }

            isTrashDeleteArmed = true
            isNextTextChangeTheOneThatShowedTrashHint = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isNextTextChangeTheOneThatShowedTrashHint = false
                self.showTrashHint()
            }
            return false
        }

        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        guard !isBusy else { return }

        if isTrashDeleteArmed, !isNextTextChangeTheOneThatShowedTrashHint {
            clearTrashDeleteState()
        }

        if helperLabel.stringValue != idleHelperText {
            helperLabel.stringValue = idleHelperText
            helperLabel.textColor = .secondaryLabelColor
        }

        pendingAutoSuffixBaseName = nil
    }

    // MARK: - Private

    // ⌘Enter and ⌃Enter don't generate insertNewline — macOS intercepts them
    // before the text field sees them. The panel handles those modified Return
    // key equivalents directly and routes them to handleSubmit with the right format.

    // Modifier-to-format mapping. ⌘Enter prefers CLI Friendly, ⌃Enter prefers
    // Markdown Code — whichever is the default falls back to No Quotes.
    //
    // | Default       | Enter       | ⌘Enter     | ⌃Enter       |
    // |---------------|-------------|------------|--------------|
    // | No Quotes     | noQuotes    | cliFriendly| markdownCode |
    // | CLI Friendly  | cliFriendly | noQuotes   | markdownCode |
    // | Markdown Code | markdownCode| cliFriendly| noQuotes     |
    private func copyFormat(from flags: NSEvent.ModifierFlags) -> CopiedPathFormat {
        let defaultFormat = AppPreferences.defaultCopiedPathFormat
        let relevantFlags = flags.intersection([.command, .control])

        if relevantFlags == .command {
            return defaultFormat == .cliFriendly ? .noQuotes : .cliFriendly
        } else if relevantFlags == .control {
            return defaultFormat == .markdownCode ? .noQuotes : .markdownCode
        } else {
            return defaultFormat
        }
    }

    private func restoreEditingWithCaretAtEnd() {
        guard window != nil else { return }

        // We select all text here not because we want to select all text, but
        // to focus the field, as the field was probably disabled before this
        // was called, which ended editing and removed active editor.
        textField.selectText(nil)

        (textField.currentEditor() as? NSTextView)?.moveToEndOfLine(nil)
    }

    private func isAllTextSelected(in textView: NSTextView) -> Bool {
        textView.selectedRange.length == textField.stringValue.count && !textField.stringValue.isEmpty
    }

    private func isCaretAtStart(in textView: NSTextView) -> Bool {
        textView.selectedRange.location == 0 && textView.selectedRange.length == 0
    }

    private func clearTrashDeleteState() {
        guard isTrashDeleteArmed else { return }
        isTrashDeleteArmed = false
        isNextTextChangeTheOneThatShowedTrashHint = false
        if helperLabel.stringValue == trashHintText {
            helperLabel.stringValue = idleHelperText
            helperLabel.textColor = .secondaryLabelColor
        }
    }

    private func showTrashHint() {
        guard isTrashDeleteArmed else { return }
        pendingAutoSuffixBaseName = nil
        helperLabel.stringValue = trashHintText
        helperLabel.textColor = .systemBlue
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.isTrashDeleteArmed else { return }
            self.clearTrashDeleteState()
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

    // MARK: - Drop Target

    private static func activateDropTarget(at screenPoint: NSPoint) {
        guard let app = runningApplication(atScreenPoint: screenPoint) else { return }
        app.activate(options: [])
    }

    // Finds the frontmost app (other than ourselves) whose window is under the
    // given screen point — i.e. the app the user just dropped onto. screenPoint
    // is in AppKit global coordinates (origin at the bottom-left of the main
    // screen); the CG window list uses a top-left origin, so the Y is flipped.
    private static func runningApplication(atScreenPoint point: NSPoint) -> NSRunningApplication? {
        let mainScreenHeight = NSScreen.screens.first?.frame.height
            ?? CGFloat(CGDisplayPixelsHigh(CGMainDisplayID()))
        let cgPoint = CGPoint(x: point.x, y: mainScreenHeight - point.y)
        let ourPID = ProcessInfo.processInfo.processIdentifier

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for info in windowList {
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  pidNumber.int32Value != ourPID,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let w = bounds["Width"] as? CGFloat,
                  let h = bounds["Height"] as? CGFloat,
                  let app = NSRunningApplication(processIdentifier: pidNumber.int32Value) else {
                continue
            }
            if CGRect(x: x, y: y, width: w, height: h).contains(cgPoint) {
                return app
            }
        }
        return nil
    }
}
