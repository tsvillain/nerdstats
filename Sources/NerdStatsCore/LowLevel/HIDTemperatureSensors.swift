import CNerdStatsPrivate
import Foundation

/// Reads temperature sensors published through the private IOHIDEventSystemClient API.
///
/// This is how Apple Silicon Macs expose CPU cluster, GPU, SoC, battery and SSD
/// temperatures without root. On Intel Macs the list is usually empty.
public final class HIDTemperatureSensors {
    private let client: IOHIDEventSystemClient
    private let services: [(service: IOHIDServiceClient, name: String)]

    public init?() {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return nil }
        // Only ask for services whose primary usage marks them as temperature sensors.
        let matching = [
            "PrimaryUsagePage": kNerdStatsHIDPageAppleVendor,
            "PrimaryUsage": kNerdStatsHIDUsageTemperatureSensor,
        ] as CFDictionary
        _ = IOHIDEventSystemClientSetMatching(client, matching)
        self.client = client

        let array = IOHIDEventSystemClientCopyServices(client) as? [AnyObject] ?? []
        services = array.compactMap { object in
            let service = unsafeBitCast(object, to: IOHIDServiceClient.self)
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String else {
                return nil
            }
            return (service, name)
        }
    }

    public var names: [String] { services.map(\.name) }

    /// Current (name, °C) pairs for sensors whose name passes `include`. Each sensor is a
    /// separate IPC round trip, so callers that need only a few should filter.
    /// Implausible values from idle or uncalibrated sensors are dropped.
    public func read(where include: (String) -> Bool = { _ in true }) -> [(name: String, celsius: Double)] {
        services.compactMap { entry in
            guard include(entry.name),
                  let event = IOHIDServiceClientCopyEvent(entry.service, kNerdStatsHIDEventTypeTemperature, 0, 0) else {
                return nil
            }
            let celsius = IOHIDEventGetFloatValue(event, kNerdStatsHIDEventFieldTemperatureLevel)
            guard celsius > 0, celsius < 150 else { return nil }
            return (entry.name, celsius)
        }
    }
}

/// Groups raw sensor names into categories the UI understands.
public enum SensorClassifier {
    public static func category(forHIDName name: String) -> TemperatureSensor.Category {
        let lower = name.lowercased()
        if lower.contains("pacc") || lower.contains("eacc") || lower.contains("cpu") { return .cpu }
        if lower.contains("gpu") { return .gpu }
        if lower.contains("battery") || lower.contains("gas gauge") { return .battery }
        if lower.contains("nand") || lower.contains("ssd") { return .storage }
        if lower.contains("soc") || lower.contains("pmu") || lower.contains("tdie") { return .soc }
        return .other
    }

    /// Several sensors can share a name (e.g. six "gas gauge battery" cells). Numbers the
    /// repeats so every sensor has a distinct label: "gas gauge battery 2", "… 3".
    public static func disambiguate(_ names: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return names.map { name in
            let count = (seen[name] ?? 0) + 1
            seen[name] = count
            return count == 1 ? name : "\(name) \(count)"
        }
    }

    /// Well-known Intel SMC temperature keys and what they measure. Each Mac model only
    /// implements a subset; missing keys are skipped.
    public static let intelSMCKeys: [(key: String, name: String, category: TemperatureSensor.Category)] = [
        ("TC0P", "CPU Proximity", .cpu),
        ("TC0D", "CPU Die", .cpu),
        ("TC0E", "CPU Die (virtual)", .cpu),
        ("TC0F", "CPU Die (filtered)", .cpu),
        ("TCXC", "CPU PECI", .cpu),
        ("TC1C", "CPU Core 1", .cpu),
        ("TC2C", "CPU Core 2", .cpu),
        ("TC3C", "CPU Core 3", .cpu),
        ("TC4C", "CPU Core 4", .cpu),
        ("TC5C", "CPU Core 5", .cpu),
        ("TC6C", "CPU Core 6", .cpu),
        ("TC7C", "CPU Core 7", .cpu),
        ("TC8C", "CPU Core 8", .cpu),
        ("TG0P", "GPU Proximity", .gpu),
        ("TG0D", "GPU Die", .gpu),
        ("TG0H", "GPU Heatsink", .gpu),
        ("TB0T", "Battery", .battery),
        ("TB1T", "Battery 1", .battery),
        ("TB2T", "Battery 2", .battery),
        ("TH0P", "SSD Proximity", .storage),
        ("TH0a", "SSD", .storage),
        ("TPCD", "Platform Controller Hub", .soc),
        ("Tm0P", "Memory Proximity", .other),
        ("TA0P", "Ambient", .other),
        ("Th0H", "Heatsink", .other),
        ("TW0P", "Wi-Fi", .other),
        ("Ts0P", "Palm Rest", .other),
    ]
}
