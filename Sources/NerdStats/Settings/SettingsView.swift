import NerdStatsCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch NerdStats at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        updateLoginItem(enabled)
                    }
                if LoginItem.needsApproval {
                    Text("Approve NerdStats in System Settings › General › Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Picker("Refresh every", selection: $settings.refreshInterval) {
                    ForEach(AppSettings.refreshIntervals, id: \.self) { interval in
                        Text(interval == 1 ? "1 second" : "\(Int(interval)) seconds").tag(interval)
                    }
                }
                Picker("Temperature unit", selection: $settings.temperatureUnit) {
                    Text("Celsius (°C)").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit (°F)").tag(TemperatureUnit.fahrenheit)
                }
            }

            Section {
                ForEach(MenuBarItem.allCases) { item in
                    Toggle(isOn: isEnabled(item)) {
                        Label(item.title, systemImage: MenuBarLayout.symbolName(for: item, values: MenuBarValues()))
                    }
                    if item == .cpu {
                        // Always present (disabled when unused) so the window keeps its height.
                        Picker("CPU shows", selection: $settings.cpuMenuBarReadout) {
                            ForEach(CPUMenuBarReadout.allCases) { readout in
                                Text(readout.title).tag(readout)
                            }
                        }
                        .disabled(!settings.menuBarItems.contains(.cpu))
                    }
                }
            } header: {
                Text("Menu bar items")
            } footer: {
                Text("Click an item to open the dashboard with that metric at the top. The battery item is hidden on Macs without a battery. With no items shown, NerdStats shows its icon instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func isEnabled(_ item: MenuBarItem) -> Binding<Bool> {
        Binding(
            get: { settings.menuBarItems.contains(item) },
            set: { enabled in
                if enabled {
                    settings.menuBarItems.insert(item)
                } else {
                    settings.menuBarItems.remove(item)
                }
            }
        )
    }

    private func updateLoginItem(_ enabled: Bool) {
        // Setting `launchAtLogin` below re-triggers onChange; ignore that echo.
        guard enabled != LoginItem.isEnabled else { return }
        do {
            try LoginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = "Could not change login item: \(error.localizedDescription)"
        }
        launchAtLogin = LoginItem.isEnabled
    }
}
