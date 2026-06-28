import Carbon

private let hotKeySignature: OSType = 0x53524348 // 'SRCH'

/// Wraps Carbon's `RegisterEventHotKey` — the standard API for global hotkeys on macOS.
///
/// Carbon is legacy, but nothing newer has replaced it for this use case. NSEvent
/// global monitors can observe but can't reliably intercept; CGEvent taps require
/// Accessibility permission (intrusive). Carbon needs no special permission and
/// delivers reliably.
///
/// Community references (Apple's own docs are legacy/sparse):
/// - https://github.com/soffes/HotKey — clean Swift wrapper around this same API
/// - https://stackoverflow.com/questions/28281653 — canonical Q&A
final class GlobalHotKey {
    private let id: UInt32
    private let handler: () -> Void
    private var hotKeyRef: EventHotKeyRef?

    private static var registry: [UInt32: GlobalHotKey] = [:]
    private static var nextId: UInt32 = 1
    private static var eventHandlerInstalled = false

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        self.id = Self.nextId
        Self.nextId += 1

        Self.installEventHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyId = EventHotKeyID(signature: hotKeySignature, id: id)

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyId,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            return
        }

        hotKeyRef = ref
        Self.registry[id] = self
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        Self.registry.removeValue(forKey: id)
    }

    // MARK: - Event Handler

    private static func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: @convention(c) (EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus = { _, event, _ in
            guard let event else { return noErr }

            var hotKeyId = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyId
            )

            DispatchQueue.main.async {
                if let hotKey = GlobalHotKey.registry[hotKeyId.id] {
                    hotKey.handler()
                }
            }

            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            nil,
            nil
        )
    }

    // MARK: - Key Codes & Modifiers

    enum KeyCode {
        static let period: UInt32 = UInt32(kVK_ANSI_Period)
        static let digits: [UInt32] = [
            UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
            UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
        ]
    }

    enum Modifiers {
        static let commandOption: UInt32 = UInt32(cmdKey | optionKey)
    }
}
