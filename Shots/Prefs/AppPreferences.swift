import Foundation

/// Thin wrapper over UserDefaults for app preferences.
enum AppPreferences {
    private static let defaults: UserDefaults = {
        let d = UserDefaults.standard
        d.register(defaults: [Keys.wrapCopiedPathsInSingleQuotes: true])
        return d
    }()

    /// Single-quotes copied paths so they paste cleanly into shell commands.
    /// Default is true because the main use case of this app is for
    /// developers taking screenshots to give to their AI agents in OpenCode
    /// etc.
    static var wrapCopiedPathsInSingleQuotes: Bool {
        get { defaults.bool(forKey: Keys.wrapCopiedPathsInSingleQuotes) }
        set { defaults.set(newValue, forKey: Keys.wrapCopiedPathsInSingleQuotes) }
    }

    private enum Keys {
        static let wrapCopiedPathsInSingleQuotes = "wrapCopiedPathsInSingleQuotes"
    }
}
