import NerdStatsCore
import SwiftUI

struct SensorsSection: View {
    @EnvironmentObject private var coordinator: StatsCoordinator
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let sensors = coordinator.snapshot.sensors
        SectionCard(title: "Temperatures & Fans", systemImage: "thermometer.medium",
                    status: StatusRules.temperature(sensors?.cpuCelsius)) {
            if let sensors {
                VStack(alignment: .leading, spacing: 4) {
                    if sensors.temperatures.isEmpty {
                        UnavailableText("No temperature sensors could be read on this Mac.")
                    } else {
                        HStack(alignment: .bottom) {
                            HeadlineValue(value: temperature(sensors.cpuCelsius), caption: "processor")
                            Sparkline(values: coordinator.history[.cpuTemperature]?.values ?? [], tint: .red)
                        }
                        StatRow("Graphics", temperature(sensors.gpuCelsius))
                        StatRow("Battery", temperature(sensors.batteryCelsius))
                    }
                    if sensors.fans.isEmpty {
                        StatRow("Fans", "none (or not reported)")
                    } else {
                        ForEach(sensors.fans) { fan in
                            StatRow("Fan \(fan.index + 1)", "\(Int(fan.rpm)) RPM")
                        }
                    }
                }
            } else {
                UnavailableText("Reading sensors…")
            }
        } detail: {
            if let sensors {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(TemperatureSensor.Category.allCases, id: \.self) { category in
                        let group = sensors.temperatures.filter { $0.category == category }
                        if !group.isEmpty {
                            Text(category.rawValue).foregroundStyle(.secondary)
                            ForEach(group) { sensor in
                                StatRow("  \(sensor.name)", temperature(sensor.celsius))
                            }
                        }
                    }
                    ForEach(sensors.fans) { fan in
                        StatRow("Fan \(fan.index + 1) range",
                                "\(fan.minRPM.map { "\(Int($0))" } ?? "–")–\(fan.maxRPM.map { "\(Int($0))" } ?? "–") RPM")
                    }
                }
            }
        }
    }

    private func temperature(_ celsius: Double?) -> String {
        guard celsius != nil else { return "unavailable" }
        return Format.temperature(celsius, unit: settings.temperatureUnit)
    }
}
