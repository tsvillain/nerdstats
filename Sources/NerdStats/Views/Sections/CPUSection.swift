import NerdStatsCore
import SwiftUI

struct CPUSection: View {
    @EnvironmentObject private var coordinator: StatsCoordinator

    var body: some View {
        let cpu = coordinator.snapshot.cpu
        SectionCard(title: "Processor", systemImage: "cpu", status: StatusRules.load(cpu?.total.total)) {
            if let cpu {
                HStack(alignment: .bottom) {
                    HeadlineValue(value: Format.percent(cpu.total.total), caption: "in use")
                    Sparkline(values: coordinator.history[.cpu]?.values ?? [], maxValue: 1)
                }
            } else {
                UnavailableText("Waiting for the first reading…")
            }
        } detail: {
            if let cpu {
                VStack(alignment: .leading, spacing: 4) {
                    StatRow("User / System / Idle",
                            "\(Format.percent(cpu.total.user)) / \(Format.percent(cpu.total.system)) / \(Format.percent(cpu.total.idle))")
                    StatRow("Load average (1, 5, 15 min)",
                            cpu.loadAverages.map { String(format: "%.2f", $0) }.joined(separator: "  "))
                    PerCoreGrid(cores: cpu.perCore)
                    ProcessList(title: "Top by CPU", processes: coordinator.snapshot.processes?.topByCPU ?? []) {
                        Format.percent($0.cpu)
                    }
                }
            }
        }
    }
}

/// One small labelled bar per logical core.
private struct PerCoreGrid: View {
    let cores: [CPUUsage]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 4) {
            ForEach(Array(cores.enumerated()), id: \.offset) { index, core in
                HStack(spacing: 4) {
                    Text("#\(index)").frame(width: 24, alignment: .leading)
                    UsageBar(fraction: core.total)
                    Text(Format.percent(core.total)).frame(width: 34, alignment: .trailing)
                }
            }
        }
    }
}

/// A short table of processes with one formatted value each. Each row offers Quit and
/// Force Quit for the user's own processes; others show a lock explaining why not.
struct ProcessList: View {
    let title: String
    let processes: [ProcessUsage]
    let value: (ProcessUsage) -> String

    @EnvironmentObject private var coordinator: StatsCoordinator
    @Environment(\.confirmProcessStop) private var confirmProcessStop
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.secondary)
            if processes.isEmpty {
                Text("Collecting…").foregroundStyle(.secondary)
            }
            ForEach(processes) { process in
                row(process)
            }
            if let failure {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(failure).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button {
                        self.failure = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss")
                }
            }
        }
    }

    private func row(_ process: ProcessUsage) -> some View {
        let permission = ProcessControl.permission(for: process)
        return HStack(spacing: 4) {
            StatRow(process.name, value(process))
            if permission.isAllowed {
                Menu {
                    actions(for: process)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Quit \(process.name) (PID \(process.pid))")
            } else {
                Image(systemName: "lock")
                    .foregroundStyle(.secondary)
                    .help(permission.reason ?? "")
            }
        }
        .contextMenu {
            if permission.isAllowed {
                actions(for: process)
            } else {
                Text(permission.reason ?? "")
            }
        }
    }

    @ViewBuilder
    private func actions(for process: ProcessUsage) -> some View {
        ForEach(ProcessStopAction.allCases) { action in
            Button("\(action.title) \(process.name)…") {
                stop(process, action: action)
            }
        }
    }

    private func stop(_ process: ProcessUsage, action: ProcessStopAction) {
        guard confirmProcessStop(process, action) else { return }
        failure = ProcessControl.stop(process, action: action).map {
            "Could not \(action.title.lowercased()) \(process.name) (PID \(process.pid)): \($0.message)"
        }
        coordinator.refreshProcesses()
    }
}
