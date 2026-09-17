import NerdStatsCore
import SwiftUI

struct MemorySection: View {
    @EnvironmentObject private var coordinator: StatsCoordinator

    var body: some View {
        let memory = coordinator.snapshot.memory
        SectionCard(title: "Memory", systemImage: "memorychip",
                    status: memory.map { StatusRules.memoryPressure($0.pressure) } ?? .unknown) {
            if let memory {
                HStack(alignment: .bottom) {
                    HeadlineValue(value: Format.memory(memory.usedBytes),
                                  caption: "used of \(Format.memory(memory.totalBytes)) · pressure \(memory.pressure.rawValue.lowercased())")
                    Sparkline(values: coordinator.history[.memory]?.values ?? [], maxValue: 1, tint: .teal)
                }
                UsageBar(fraction: memory.usedFraction, tint: .teal)
            } else {
                UnavailableText("Waiting for the first reading…")
            }
        } detail: {
            if let memory {
                VStack(alignment: .leading, spacing: 2) {
                    StatRow("App memory", Format.memory(memory.appBytes))
                    StatRow("Wired", Format.memory(memory.wiredBytes))
                    StatRow("Compressed", Format.memory(memory.compressedBytes))
                    StatRow("Cached files", Format.memory(memory.cachedBytes))
                    StatRow("Free", Format.memory(memory.freeBytes))
                    StatRow("Swap used", "\(Format.memory(memory.swapUsedBytes)) of \(Format.memory(memory.swapTotalBytes))")
                    ProcessList(title: "Top by memory", processes: coordinator.snapshot.processes?.topByMemory ?? []) {
                        Format.memory($0.memoryBytes)
                    }
                }
            }
        }
    }
}
