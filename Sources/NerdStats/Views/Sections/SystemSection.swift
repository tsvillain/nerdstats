import NerdStatsCore
import SwiftUI

struct SystemSection: View {
    @EnvironmentObject private var coordinator: StatsCoordinator

    var body: some View {
        if let system = coordinator.snapshot.system {
            SectionCard(title: "This Mac", systemImage: "laptopcomputer") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(system.modelName).font(.body.weight(.medium))
                    StatRow("Chip", system.chipName)
                    StatRow("Memory", Format.memory(system.memoryBytes))
                    StatRow("macOS", system.osVersion)
                    StatRow("Up for", system.uptime.map { Format.duration(seconds: $0) } ?? "–")
                }
            } detail: {
                VStack(alignment: .leading, spacing: 2) {
                    StatRow("Model ID", system.modelIdentifier)
                    StatRow("Architecture", system.architecture.rawValue + (system.isTranslated ? " (Rosetta)" : ""))
                    StatRow("Cores", "\(system.physicalCores) physical / \(system.logicalCores) logical")
                    ForEach(system.coreClusters, id: \.name) { cluster in
                        StatRow("  \(cluster.name) cores", "\(cluster.physicalCores)")
                    }
                    StatRow("Hostname", system.hostName)
                }
            }
        }
    }
}
