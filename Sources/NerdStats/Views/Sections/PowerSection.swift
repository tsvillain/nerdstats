import NerdStatsCore
import SwiftUI

/// Hidden entirely on Macs without a battery.
struct PowerSection: View {
    @EnvironmentObject private var coordinator: StatsCoordinator
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        if let power = coordinator.snapshot.power {
            SectionCard(title: "Battery", systemImage: batteryIcon(power), status: healthStatus(power)) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .bottom) {
                        HeadlineValue(value: Format.percent(power.chargeFraction), caption: stateText(power))
                        Spacer()
                        if let health = power.health {
                            HeadlineValue(value: Format.percent(health), caption: "health")
                        }
                    }
                    UsageBar(fraction: power.chargeFraction ?? 0, tint: .green)
                    if let watts = power.systemWatts {
                        StatRow("Using", Format.watts(watts))
                    }
                }
            } detail: {
                VStack(alignment: .leading, spacing: 2) {
                    StatRow("Cycle count", power.cycleCount.map(String.init) ?? "–")
                    StatRow("Capacity", capacityText(power))
                    StatRow("Temperature", Format.temperature(power.temperatureCelsius, unit: settings.temperatureUnit))
                    StatRow("Voltage", power.voltage.map { String(format: "%.2f V", $0) } ?? "–")
                    StatRow("Battery power", Format.watts(power.batteryWatts))
                    StatRow("Adapter", power.isPluggedIn ? "\(Format.watts(power.adapterWatts)) \(power.adapterName ?? "")" : "not connected")
                    Text("System power").foregroundStyle(.secondary)
                    Sparkline(values: coordinator.history[.systemPower]?.values ?? [], tint: .yellow)
                }
            }
        }
    }

    private func stateText(_ power: PowerReading) -> String {
        if power.isCharging {
            return power.minutesToFull.map { "charging · full in \(Format.duration(seconds: TimeInterval($0 * 60)))" } ?? "charging"
        }
        if power.isPluggedIn {
            return power.isFullyCharged ? "fully charged" : "plugged in, not charging"
        }
        return power.minutesToEmpty.map { "\(Format.duration(seconds: TimeInterval($0 * 60))) remaining" } ?? "on battery"
    }

    private func capacityText(_ power: PowerReading) -> String {
        guard let max = power.maxCapacitymAh, let design = power.designCapacitymAh else { return "–" }
        return "\(max) of \(design) mAh"
    }

    /// Apple considers a battery worn once it holds less than 80% of its design capacity.
    private func healthStatus(_ power: PowerReading) -> StatusLevel {
        guard let health = power.health else { return .unknown }
        return health >= 0.8 ? .normal : .busy
    }

    private func batteryIcon(_ power: PowerReading) -> String {
        if power.isCharging { return "battery.100.bolt" }
        switch power.chargeFraction ?? 0 {
        case ..<0.13: return "battery.0"
        case ..<0.38: return "battery.25"
        case ..<0.63: return "battery.50"
        case ..<0.88: return "battery.75"
        default: return "battery.100"
        }
    }
}
