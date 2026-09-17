import NerdStatsCore
import SwiftUI

/// The popover shown when the menu bar item is clicked.
struct DashboardView: View {
    @EnvironmentObject private var coordinator: StatsCoordinator
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openSettingsWindow) private var openSettingsWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    SystemSection()
                    CPUSection()
                    GPUSection()
                    MemorySection()
                    DiskSection()
                    NetworkSection()
                    PowerSection()
                    SensorsSection()
                }
                .padding(12)
            }
            .frame(height: 560)
            Divider()
            footer
        }
        .frame(width: 400)
        // The coordinator only samples everything while this view is on screen.
        .onAppear { coordinator.dashboardDidAppear() }
        .onDisappear { coordinator.dashboardDidDisappear() }
    }

    private var overall: StatusLevel {
        OverallStatus.level(for: coordinator.snapshot)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("NerdStats").font(.title3.weight(.semibold))
                Text(OverallStatus.sentence(for: overall))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(level: overall)
            Toggle("Nerd", isOn: $settings.nerdMode)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Show raw per-core, per-sensor and per-process numbers")
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Text("Updated \(coordinator.snapshot.timestamp.formatted(date: .omitted, time: .standard))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Combines the per-subsystem statuses into one headline verdict.
enum OverallStatus {
    static func level(for snapshot: SystemSnapshot) -> StatusLevel {
        StatusRules.worst([
            StatusRules.load(snapshot.cpu?.total.total),
            StatusRules.temperature(snapshot.sensors?.cpuCelsius),
            snapshot.memory.map { StatusRules.memoryPressure($0.pressure) } ?? .unknown,
        ])
    }

    static func sentence(for level: StatusLevel) -> String {
        switch level {
        case .normal: return "Your Mac is running smoothly."
        case .busy: return "Your Mac is working hard right now."
        case .hot: return "Your Mac is under heavy strain or running hot."
        case .unknown: return "Gathering data…"
        }
    }
}
