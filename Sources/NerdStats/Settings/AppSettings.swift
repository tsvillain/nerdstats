import Foundation
import NerdStatsCore

/// What the menu bar item shows next to (or instead of) the icon.
enum MenuBarReadout: String, CaseIterable, Identifiable {
    case icon
    case cpu
    case temperature
    case cpuAndTemperature
    case memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: return "Icon only"
        case .cpu: return "CPU usage"
        case .temperature: return "CPU temperature"
        case .cpuAndTemperature: return "CPU usage and temperature"
        case .memory: return "Memory usage"
        }
    }

    /// Subsystems that must keep sampling while the dashboard is closed.
    var requiredSubsystems: Set<Subsystem> {
        switch self {
        case .icon, .cpu: return [.cpu]
        case .temperature, .cpuAndTemperature: return [.cpu, .processorTemperature]
        case .memory: return [.cpu, .memory]
        }
    }
}

/// User preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let refreshIntervals: [TimeInterval] = [1, 2, 5, 10]

    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let menuBarReadout = "menuBarReadout"
        static let temperatureUnit = "temperatureUnit"
        static let nerdMode = "nerdMode"
    }

    private let defaults: UserDefaults

    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    @Published var menuBarReadout: MenuBarReadout {
        didSet { defaults.set(menuBarReadout.rawValue, forKey: Key.menuBarReadout) }
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
        menuBarReadout = defaults.string(forKey: Key.menuBarReadout).flatMap(MenuBarReadout.init) ?? .cpuAndTemperature
        temperatureUnit = defaults.string(forKey: Key.temperatureUnit).flatMap(TemperatureUnit.init) ?? .celsius
        nerdMode = defaults.bool(forKey: Key.nerdMode)
    }
}
