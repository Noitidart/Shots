import Foundation

// MARK: - Target

enum ScreenCaptureTarget {
    case directory(URL)
    case nonFolder(label: String)
}

// MARK: - Monitor

@MainActor
final class ScreenCaptureTargetMonitor {
    private var watcher: DirectoryWatcher?
    private var currentTarget: ScreenCaptureTarget?
    private var fingerprint: FileContentFingerprint?

    private let domain = "com.apple.screencapture" as CFString
    private let preferencesDir: URL
    private let preferencesPlistURL: URL

    init() {
        self.preferencesDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Preferences", isDirectory: true)
        self.preferencesPlistURL = preferencesDir
            .appendingPathComponent("com.apple.screencapture.plist")
    }

    func start(onChange: @escaping @MainActor (ScreenCaptureTarget) -> Void) throws {
        // Initial fire: resolve and announce the current target immediately.
        let target = getCurrentTargetFromSystemPrefs()
        currentTarget = target
        onChange(target)

        // Initialize the fingerprint so future comparisons have a baseline.
        fingerprint = readPrefsFileFingerprint()

        // Watch for changes. Two gates inside onChange:
        // 1. didScreenshotPrefsFileChange — did the screencapture plist file actually change (mtime + size)?
        // 2. isTargetDifferentThanCurrentTarget — is the resolved target actually different from what we already announced?
        watcher = try DirectoryWatcher(directoryURL: preferencesDir) { [weak self] in
            guard let self else { return }
            guard self.didScreenshotPrefsFileChange() else { return }

            let newTarget = self.getCurrentTargetFromSystemPrefs()
            guard self.isTargetDifferentThanCurrentTarget(newTarget) else { return }

            self.currentTarget = newTarget
            onChange(newTarget)
        }
        watcher?.start()
    }

    // MARK: - Resolution (reads com.apple.screencapture preferences)

    private func getCurrentTargetFromSystemPrefs() -> ScreenCaptureTarget {
        CFPreferencesAppSynchronize(domain)

        if let target = CFPreferencesCopyAppValue("target" as CFString, domain) as? String,
           target != "file" {
            let label = target == "clipboard" ? "Clipboard" : target.capitalized
            return .nonFolder(label: label)
        }

        let location = CFPreferencesCopyAppValue("location" as CFString, domain) as? String
        guard let location, !location.isEmpty else {
            // No location set — macOS defaults to the Desktop.
            // If FileManager can't resolve it, report honestly rather than guess.
            guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
                return .nonFolder(label: "Unknown")
            }
            return .directory(desktopURL)
        }

        let expanded = (location as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let label = url.lastPathComponent.isEmpty
            ? "Configured screenshot location"
            : url.lastPathComponent

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .nonFolder(label: label)
        }

        return .directory(URL(fileURLWithPath: expanded, isDirectory: true))
    }

    // MARK: - Plist Change Detection

    private func didScreenshotPrefsFileChange() -> Bool {
        let newFingerprint = readPrefsFileFingerprint()
        let changed = newFingerprint != fingerprint
        fingerprint = newFingerprint
        return changed
    }

    private func readPrefsFileFingerprint() -> FileContentFingerprint? {
        guard let values = try? preferencesPlistURL.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else {
            return nil
        }
        return FileContentFingerprint(modificationDate: values.contentModificationDate, fileSize: values.fileSize)
    }

    // MARK: - Target Comparison

    private func isTargetDifferentThanCurrentTarget(_ newTarget: ScreenCaptureTarget) -> Bool {
        switch (currentTarget, newTarget) {
        case let (.directory(oldURL), .directory(newURL)):
            return oldURL.path != newURL.path
        case let (.nonFolder(oldLabel), .nonFolder(newLabel)):
            return oldLabel != newLabel
        default:
            return true
        }
    }
}

// MARK: - File Content Fingerprint

private struct FileContentFingerprint: Equatable {
    let modificationDate: Date?
    let fileSize: Int?
}
