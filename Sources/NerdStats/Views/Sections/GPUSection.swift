import NerdStatsCore
import SwiftUI

struct GPUSection: View {
    @EnvironmentObject private var coordinator: StatsCoordinator

    var body: some View {
        let gpus = coordinator.snapshot.gpus ?? []
        let busiest = gpus.compactMap(\.utilization).max()
        SectionCard(title: "Graphics", systemImage: "rectangle.3.group", status: StatusRules.load(busiest)) {
            if gpus.isEmpty {
                UnavailableText("GPU statistics are not available on this Mac.")
            } else {
                HStack(alignment: .bottom) {
                    HeadlineValue(value: Format.percent(busiest), caption: gpus.count == 1 ? gpus[0].name : "busiest GPU")
                    Sparkline(values: coordinator.history[.gpu]?.values ?? [], maxValue: 1, tint: .purple)
                }
            }
        } detail: {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(gpus) { gpu in
                    StatRow(gpu.name, Format.percent(gpu.utilization))
                    StatRow("  Memory in use", memoryText(gpu))
                }
            }
        }
    }

    private func memoryText(_ gpu: GPUReading) -> String {
        guard let used = gpu.memoryUsedBytes else { return "unavailable" }
        guard let total = gpu.memoryTotalBytes else { return Format.memory(used) }
        return "\(Format.memory(used)) of \(Format.memory(total))"
    }
}
