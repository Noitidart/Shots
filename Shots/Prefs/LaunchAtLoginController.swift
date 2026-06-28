import ServiceManagement

/// Wraps SMAppService for registering/unregistering launch-at-login.
///
/// SMAppService (macOS 13+) replaced the deprecated login-items approach
/// (LSSharedFileList, SMLoginItemSetEnabled). It needs no helper bundle —
/// the main app registers itself directly.
///
/// Docs: https://developer.apple.com/documentation/servicemanagement/smappservice
enum LaunchAtLoginController {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func enable() -> Bool {
        do {
            try SMAppService.mainApp.register()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func disable() -> Bool {
        do {
            try SMAppService.mainApp.unregister()
            return true
        } catch {
            return false
        }
    }
}
