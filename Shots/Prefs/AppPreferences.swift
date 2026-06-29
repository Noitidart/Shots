import Foundation

// MARK: - Copied Path Format

/// How a screenshot path is wrapped when copied to the clipboard.
enum CopiedPathFormat: String, CaseIterable {
    /// Raw path, no surrounding characters. For Finder (Cmd+Shift+G) and apps
    /// that don't understand quotes.
    case noQuotes
    /// Single-quotes the path only when it contains spaces, so it pastes cleanly
    /// into terminal commands.
    case cliFriendly
    /// Wraps the path in backticks (markdown inline code) so coding agents treat
    /// it as text instead of attaching the image.
    case markdownCode

    func wrap(_ path: String) -> String {
        switch self {
        case .noQuotes:
            return path
        case .cliFriendly:
            return path.contains(" ") ? "'\(path)'" : path
        case .markdownCode:
            return "`\(path)`"
        }
    }

    var menuDisplayName: String {
        switch self {
        case .noQuotes:
            return "Copy Paths without Quotes"
        case .cliFriendly:
            return "Copy Paths with CLI Friendly Quotes"
        case .markdownCode:
            return "Copy Paths as Markdown Code (Anti Coding Agent Auto-Attach)"
        }
    }

    var shortName: String {
        switch self {
        case .noQuotes:
            return "no quotes"
        case .cliFriendly:
            return "CLI"
        case .markdownCode:
            return "Markdown Code"
        }
    }
}

// MARK: - App Preferences

/// Thin wrapper over UserDefaults for app preferences.
enum AppPreferences {
    private static let defaults: UserDefaults = {
        let d = UserDefaults.standard
        d.register(defaults: [Keys.defaultCopiedPathFormat: CopiedPathFormat.markdownCode.rawValue])
        return d
    }()

    static var defaultCopiedPathFormat: CopiedPathFormat {
        get {
            let raw = defaults.string(forKey: Keys.defaultCopiedPathFormat) ?? CopiedPathFormat.markdownCode.rawValue
            return CopiedPathFormat(rawValue: raw) ?? .markdownCode
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.defaultCopiedPathFormat) }
    }

    private enum Keys {
        static let defaultCopiedPathFormat = "defaultCopiedPathFormat"
    }
}
