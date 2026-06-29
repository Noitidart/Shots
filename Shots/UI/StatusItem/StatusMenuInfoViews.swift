import AppKit

/// A non-interactive header row for the menu — shows the target name.
/// Custom view instead of a disabled NSMenuItem because disabled items
/// are faded by AppKit, which reads as "broken command" not "information."
final class StatusMenuHeaderView: NSView {
    init(text: String) {
        // 22pt matches a standard NSMenuItem row height so the header blends in natively.
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 22))

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// A non-interactive multi-line note row for the menu — smaller, dimmer text
/// for explanatory information (e.g. how to fix a non-folder target).
final class StatusMenuNoteView: NSView {
    init(text: String) {
        // 22pt matches a standard NSMenuItem row height so the note blends in natively.
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 22))

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
