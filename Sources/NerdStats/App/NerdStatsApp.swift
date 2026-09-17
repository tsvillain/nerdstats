import AppKit
import NerdStatsCore

/// The menu bar app. There is no Dock icon or main window (LSUIElement in Info.plist);
/// everything lives in the status items, their dashboard popover and the Settings window.
enum NerdStatsApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // `delegate` is weak on NSApplication; this local keeps it alive while `run` loops.
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    lazy var coordinator = StatsCoordinator(settings: settings)
    lazy var settingsWindow = SettingsWindowController(settings: settings)
    private var statusItems: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.enableOnFirstRun()
        statusItems = StatusItemController(coordinator: coordinator, settings: settings) { [weak self] in
            self?.settingsWindow.show()
        }
        coordinator.start()
    }
}
