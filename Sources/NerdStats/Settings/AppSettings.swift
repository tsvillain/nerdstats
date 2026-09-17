import Foundation
import NerdStatsCore

/// User preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let refreshIntervals: [TimeInterval] = [1, 2, 5, 10]

    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let menuBarItems = "menuBarItems"
        static let cpuMenuBarReadout = "cpuMenuBarReadout"
        /// The single "Menu bar shows" choice from before items could be enabled separately.
        static let legacyMenuBarReadout = "menuBarReadout"
        static let temperatureUnit = "temperatureUnit"
        static let nerdMode = "nerdMode"
    }

    private let defaults: UserDefaults

    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    /// Metrics with their own menu bar item. When none is visible the app icon is shown instead.
    @Published var menuBarItems: Set<MenuBarItem> {
        didSet {
            defaults.set(MenuBarItem.allCases.filter(menuBarItems.contains).map(\.rawValue), forKey: Key.menuBarItems)
        }
    }

    @Published var cpuMenuBarReadout: CPUMenuBarReadout {
        didSet { defaults.set(cpuMenuBarReadout.rawValue, forKey: Key.cpuMenuBarReadout) }
    }

    @Published var temperatureUnit: TemperatureUnit {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: Key.temperatureUnit) }
    }

    /// Shows raw per-core, per-sensor and per-process details in the dashboard.
    @Published var nerdMode: Bool {
        didSet { defaults.set(nerdMode, forKey: Key.nerdMode) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let interval = defaults.double(forKey: Key.refreshInterval)
        refreshInterval = Self.refreshIntervals.contains(interval) ? interval : 2
        let menuBar = MenuBarPreferences.resolve(
            storedItems: defaults.stringArray(forKey: Key.menuBarItems),
            storedCPUReadout: defaults.string(forKey: Key.cpuMenuBarReadout),
            legacyReadout: defaults.string(forKey: Key.legacyMenuBarReadout)
        )
        menuBarItems = menuBar.items
        cpuMenuBarReadout = menuBar.cpuReadout
        temperatureUnit = defaults.string(forKey: Key.temperatureUnit).flatMap(TemperatureUnit.init) ?? .celsius
        nerdMode = defaults.bool(forKey: Key.nerdMode)
    }
}
