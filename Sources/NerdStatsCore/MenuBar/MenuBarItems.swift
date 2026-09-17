import Foundation

/// A metric that can have its own item in the menu bar. Items appear left to right in
/// declaration order.
public enum MenuBarItem: String, CaseIterable, Sendable, Identifiable {
    case cpu, gpu, memory, storage, battery

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .storage: return "SSD"
        case .battery: return "Battery"
        }
    }

    /// The dashboard section this item opens at the top.
    public var dashboardSection: DashboardSection {
        switch self {
        case .cpu: return .processor
        case .gpu: return .graphics
        case .memory: return .memory
        case .storage: return .storage
        case .battery: return .battery
        }
    }
}

/// What the CPU item shows next to its icon.
public enum CPUMenuBarReadout: String, CaseIterable, Sendable, Identifiable {
    case usage, temperature, usageAndTemperature

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .usage: return "Usage"
        case .temperature: return "Temperature"
        case .usageAndTemperature: return "Usage and temperature"
        }
    }
}

/// The dashboard's sections, in their default order.
public enum DashboardSection: CaseIterable, Sendable {
    case system, processor, graphics, memory, storage, network, battery, sensors

    /// Default order with `focus`, if any, moved to the top.
    public static func ordered(focus: MenuBarItem?) -> [DashboardSection] {
        guard let first = focus?.dashboardSection else { return allCases }
        return [first] + allCases.filter { $0 != first }
    }
}

/// The values menu bar items display, rounded to what is shown so that an unchanged
/// readout compares equal and never triggers a redraw.
public struct MenuBarValues: Equatable, Sendable {
    public var cpuPercent: Int?
    public var cpuCelsius: Int?
    public var gpuPercent: Int?
    public var memoryUsedPercent: Int?
    public var storageUsedPercent: Int?
    public var batteryPercent: Int?
    public var isCharging = false
    /// `nil` until power has been sampled at least once.
    public var hasBattery: Bool?

    public init() {}

    /// Reads only what `sampled` refreshed; the rest stays unknown so a stale value from an
    /// earlier dashboard session is never shown as current.
    public init(snapshot: SystemSnapshot, sampled: Set<Subsystem>) {
        func percent(_ fraction: Double?) -> Int? {
            guard let fraction, fraction.isFinite else { return nil }
            return Int((fraction * 100).rounded())
        }
        cpuPercent = percent(snapshot.cpu?.total.total)
        if !sampled.isDisjoint(with: [.sensors, .processorTemperature]),
           let celsius = snapshot.sensors?.cpuCelsius, celsius.isFinite {
            cpuCelsius = Int(celsius.rounded())
        }
        if sampled.contains(.gpu) {
            gpuPercent = percent(snapshot.gpus?.compactMap(\.utilization).max())
        }
        if sampled.contains(.memory) {
            memoryUsedPercent = percent(snapshot.memory?.usedFraction)
        }
        if sampled.contains(.disk) {
            storageUsedPercent = percent(Self.startupVolume(snapshot.disk?.volumes ?? [])?.usedFraction)
        }
        if sampled.contains(.power) {
            hasBattery = snapshot.power != nil
            batteryPercent = percent(snapshot.power?.chargeFraction)
            isCharging = snapshot.power?.isCharging ?? false
        }
    }

    /// The volume macOS boots from, or the first internal volume if "/" is not listed.
    static func startupVolume(_ volumes: [VolumeInfo]) -> VolumeInfo? {
        volumes.first { $0.mountPath == "/" } ?? volumes.first { $0.isInternal }
    }
}

/// Pure decisions behind the menu bar items: which are shown, what they say, and what has
/// to keep sampling while the dashboard is closed.
public enum MenuBarLayout {
    /// Enabled items that should be visible. The battery item hides once power sampling
    /// shows the Mac has no battery. An empty result means the app shows its plain icon
    /// instead, so Settings and Quit always stay reachable.
    public static func visibleItems(enabled: Set<MenuBarItem>, hasBattery: Bool?) -> [MenuBarItem] {
        MenuBarItem.allCases.filter { item in
            enabled.contains(item) && !(item == .battery && hasBattery == false)
        }
    }

    /// Subsystems to sample while the dashboard is closed. CPU ticks are always kept warm,
    /// as before, so the dashboard's headline usage is ready the moment it opens.
    public static func requiredSubsystems(enabled: Set<MenuBarItem>, cpuReadout: CPUMenuBarReadout) -> Set<Subsystem> {
        var subsystems: Set<Subsystem> = [.cpu]
        if enabled.contains(.cpu), cpuReadout != .usage { subsystems.insert(.processorTemperature) }
        if enabled.contains(.gpu) { subsystems.insert(.gpu) }
        if enabled.contains(.memory) { subsystems.insert(.memory) }
        if enabled.contains(.storage) { subsystems.insert(.disk) }
        if enabled.contains(.battery) { subsystems.insert(.power) }
        return subsystems
    }

    /// The compact value shown next to an item's icon, e.g. "42%" or "42% 61°C".
    public static func text(for item: MenuBarItem, values: MenuBarValues,
                            cpuReadout: CPUMenuBarReadout, unit: TemperatureUnit) -> String {
        func percent(_ value: Int?) -> String { value.map { "\($0)%" } ?? "–" }
        switch item {
        case .cpu:
            let usage = percent(values.cpuPercent)
            let temperature = Format.temperature(values.cpuCelsius.map { Double($0) }, unit: unit)
            switch cpuReadout {
            case .usage: return usage
            case .temperature: return temperature
            case .usageAndTemperature: return "\(usage) \(temperature)"
            }
        case .gpu: return percent(values.gpuPercent)
        case .memory: return percent(values.memoryUsedPercent)
        case .storage: return percent(values.storageUsedPercent)
        case .battery: return percent(values.batteryPercent)
        }
    }

    /// SF Symbol for an item. Each metric has its own shape so items stay distinguishable
    /// side by side; the battery symbol also reflects the charge level.
    public static func symbolName(for item: MenuBarItem, values: MenuBarValues) -> String {
        switch item {
        case .cpu: return "cpu"
        case .gpu: return "rectangle.3.group"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .battery:
            if values.isCharging { return "battery.100.bolt" }
            guard let percent = values.batteryPercent else { return "battery.100" }
            switch percent {
            case ..<13: return "battery.0"
            case ..<38: return "battery.25"
            case ..<63: return "battery.50"
            case ..<88: return "battery.75"
            default: return "battery.100"
            }
        }
    }

    /// Symbol for the fallback item shown when no metric item is visible.
    public static let appSymbolName = "gauge.medium"
}

/// Turns stored preferences into menu bar item settings, migrating the single
/// "Menu bar shows" choice used before items could be enabled separately.
public enum MenuBarPreferences {
    public static let defaultItems: Set<MenuBarItem> = [.cpu]
    public static let defaultCPUReadout: CPUMenuBarReadout = .usageAndTemperature

    /// - Parameters:
    ///   - storedItems: raw values saved by this version; an empty array means the user turned
    ///     every item off, `nil` means nothing has been saved yet.
    ///   - storedCPUReadout: raw `CPUMenuBarReadout` saved by this version.
    ///   - legacyReadout: raw value of the old single setting (`icon`, `cpu`, `temperature`,
    ///     `cpuAndTemperature` or `memory`).
    public static func resolve(storedItems: [String]?, storedCPUReadout: String?,
                               legacyReadout: String?) -> (items: Set<MenuBarItem>, cpuReadout: CPUMenuBarReadout) {
        let legacy = legacyReadout.flatMap(migrate)
        let items = storedItems.map { Set($0.compactMap(MenuBarItem.init)) }
            ?? legacy?.items
            ?? defaultItems
        let cpuReadout = storedCPUReadout.flatMap(CPUMenuBarReadout.init)
            ?? legacy?.cpuReadout
            ?? defaultCPUReadout
        return (items, cpuReadout)
    }

    private static func migrate(_ legacy: String) -> (items: Set<MenuBarItem>, cpuReadout: CPUMenuBarReadout)? {
        switch legacy {
        // No metric items leaves just the app icon, as before.
        case "icon": return ([], defaultCPUReadout)
        case "cpu": return ([.cpu], .usage)
        case "temperature": return ([.cpu], .temperature)
        case "cpuAndTemperature": return ([.cpu], .usageAndTemperature)
        case "memory": return ([.memory], defaultCPUReadout)
        default: return nil
        }
    }
}
