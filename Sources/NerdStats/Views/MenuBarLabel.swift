import NerdStatsCore
import SwiftUI

/// The few values the menu bar item can show, rounded to what is displayed so that
/// unchanged text never triggers a redraw.
@MainActor
final class MenuBarModel: ObservableObject {
    struct Values: Equatable {
        var cpuPercent: Int?
        var cpuCelsius: Int?
        var memoryPercent: Int?
    }

    @Published private(set) var values = Values()

    func update(with snapshot: SystemSnapshot) {
        let new = Values(
            cpuPercent: snapshot.cpu.map { Int(($0.total.total * 100).rounded()) },
            cpuCelsius: snapshot.sensors?.cpuCelsius.map { Int($0.rounded()) },
            memoryPercent: snapshot.memory.map { Int(($0.usedFraction * 100).rounded()) }
        )
        if new != values {
            values = new
        }
    }
}

/// The compact readout in the menu bar.
struct MenuBarLabel: View {
    @EnvironmentObject private var model: MenuBarModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        if settings.menuBarReadout == .icon {
            Image(systemName: "gauge.medium")
        } else {
            Text(text).monospacedDigit()
        }
    }

    private var text: String {
        let values = model.values
        let cpu = values.cpuPercent.map { "\($0)%" } ?? "–"
        let temperature = Format.temperature(values.cpuCelsius.map { Double($0) }, unit: settings.temperatureUnit)
        switch settings.menuBarReadout {
        case .icon: return ""
        case .cpu: return "CPU \(cpu)"
        case .temperature: return temperature
        case .cpuAndTemperature: return "\(cpu) · \(temperature)"
        case .memory: return "MEM \(values.memoryPercent.map { "\($0)%" } ?? "–")"
        }
    }
}
