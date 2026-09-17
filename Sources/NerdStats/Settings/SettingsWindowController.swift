import AppKit
import SwiftUI

/// Hosts `SettingsView` in a plain AppKit window.
///
/// SwiftUI's `Settings` scene cannot be opened reliably from a menu bar–only app on every
/// macOS version from 13 onward, so the window is managed directly.
@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "NerdStats Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView().environmentObject(settings))
            window.center()
            self.window = window
        }
        // An accessory app must activate itself, or the window opens behind other apps.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
