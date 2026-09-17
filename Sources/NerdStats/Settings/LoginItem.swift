import Foundation
import ServiceManagement

/// Launch-at-login via `SMAppService.mainApp` (macOS 13+). The app shows up under
/// System Settings › General › Login Items, where the user can also turn it off.
enum LoginItem {
    private static let didApplyDefaultKey = "didApplyDefaultLoginItem"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the user must approve the item in System Settings before it takes effect.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Turns launch-at-login on the first time the app runs. Later launches respect
    /// whatever the user chose. If registration fails, the next launch tries again.
    static func enableOnFirstRun(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: didApplyDefaultKey) else { return }
        do {
            try setEnabled(true)
            defaults.set(true, forKey: didApplyDefaultKey)
        } catch {
            NSLog("NerdStats: could not enable launch at login: \(error.localizedDescription)")
        }
    }
}
