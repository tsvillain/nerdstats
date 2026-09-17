import AppKit
import NerdStatsCore
import SwiftUI

/// The menu bar app. There is no Dock icon or main window (LSUIElement in Info.plist);
/// everything lives in the MenuBarExtra and the Settings window.
struct NerdStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(appDelegate.coordinator)
                .environmentObject(appDelegate.settings)
                .environment(\.openSettingsWindow) { appDelegate.settingsWindow.show() }
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.coordinator.menuBar)
                .environmentObject(appDelegate.settings)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    lazy var coordinator = StatsCoordinator(settings: settings)
    lazy var settingsWindow = SettingsWindowController(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.enableOnFirstRun()
        coordinator.start()
    }
}
