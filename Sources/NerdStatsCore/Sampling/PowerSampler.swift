import Foundation
import IOKit
import IOKit.ps

/// Battery state and power flow from the AppleSmartBattery registry entry.
/// Returns `nil` on Macs without a battery.
public final class PowerSampler: Sampler {
    public init() {}

    public func sample() -> PowerReading? {
        guard let service = IORegistry.firstService(matching: "AppleSmartBattery") else { return nil }
        defer { IOObjectRelease(service) }
        let properties = IORegistry.properties(of: service)
        let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
        return BatteryParser.parse(properties, adapter: adapter)
    }
}

/// Converts raw AppleSmartBattery properties into a `PowerReading`. Kept separate from
/// IOKit access so it can be tested with recorded dictionaries.
public enum BatteryParser {
    public static func parse(_ properties: [String: Any], adapter: [String: Any]?) -> PowerReading? {
        guard properties.bool("BatteryInstalled") != false else { return nil }
        let batteryData = properties.dictionary("BatteryData") ?? [:]
        let telemetry = properties.dictionary("PowerTelemetryData") ?? [:]

        let isPluggedIn = properties.bool("ExternalConnected") ?? false
        let isCharging = properties.bool("IsCharging") ?? false

        // Apple Silicon reports MaxCapacity as a percentage, so prefer the mAh figures.
        // NominalChargeCapacity is what System Settings uses for "Maximum Capacity".
        let maxCapacity = properties.int("NominalChargeCapacity")
            ?? batteryData.int("NominalChargeCapacity")
            ?? properties.int("AppleRawMaxCapacity")
            ?? properties.int("MaxCapacity")
        let designCapacity = properties.int("DesignCapacity") ?? batteryData.int("DesignCapacity")

        var batteryWatts: Double?
        if let millivolts = properties.int64("Voltage"), let rawAmps = properties.int64("InstantAmperage") {
            batteryWatts = BatteryMath.watts(millivolts: millivolts, milliamps: BatteryMath.signed(rawAmps))
        }

        // SystemPowerIn (mW) is the total draw measured at the input on Apple Silicon while
        // on adapter power. On battery, the discharge rate is the system's draw.
        var systemWatts: Double?
        if let systemPowerIn = telemetry.int64("SystemPowerIn"), systemPowerIn > 0 {
            systemWatts = Double(systemPowerIn) / 1000
        } else if !isPluggedIn, let batteryWatts, batteryWatts < 0 {
            systemWatts = -batteryWatts
        }

        return PowerReading(
            chargeFraction: BatteryMath.chargeFraction(current: properties.int("CurrentCapacity"),
                                                       max: properties.int("MaxCapacity")),
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            isFullyCharged: properties.bool("FullyCharged") ?? false,
            minutesToEmpty: isPluggedIn ? nil : BatteryMath.minutesRemaining(properties.int("TimeRemaining")),
            minutesToFull: isCharging ? BatteryMath.minutesRemaining(properties.int("TimeRemaining")) : nil,
            cycleCount: properties.int("CycleCount"),
            health: BatteryMath.health(maxCapacity: maxCapacity, designCapacity: designCapacity),
            maxCapacitymAh: maxCapacity,
            designCapacitymAh: designCapacity,
            // Reported in hundredths of a degree Celsius when present.
            temperatureCelsius: properties.int64("Temperature").map { Double($0) / 100 },
            adapterWatts: isPluggedIn ? adapter?.int64("Watts").map { Double($0) } : nil,
            adapterName: isPluggedIn ? adapter?["Name"] as? String : nil,
            batteryWatts: batteryWatts,
            systemWatts: systemWatts,
            voltage: properties.int64("Voltage").map { Double($0) / 1000 }
        )
    }
}
