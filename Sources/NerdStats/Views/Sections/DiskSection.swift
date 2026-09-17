import NerdStatsCore
import SwiftUI

struct DiskSection: View {
    @EnvironmentObject private var coordinator: StatsCoordinator

    var body: some View {
        let disk = coordinator.snapshot.disk
        let volumes = disk?.volumes ?? []
        SectionCard(title: "Storage", systemImage: "internaldrive",
                    status: StatusRules.worst(volumes.map { StatusRules.diskUsage($0.usedFraction) })) {
            if let disk {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(volumes) { volume in
                        VStack(alignment: .leading, spacing: 2) {
                            StatRow(volume.name, "\(Format.bytes(volume.availableBytes)) free of \(Format.bytes(volume.totalBytes))")
                            UsageBar(fraction: volume.usedFraction, tint: .blue)
                        }
                    }
                    HStack {
                        StatRow("Read", Format.rate(disk.readBytesPerSecond))
                        StatRow("Write", Format.rate(disk.writeBytesPerSecond))
                    }
                }
            } else {
                UnavailableText("Waiting for the first reading…")
            }
        } detail: {
            if let disk {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Read").foregroundStyle(.secondary)
                    Sparkline(values: coordinator.history[.diskRead]?.values ?? [], tint: .blue)
                    Text("Write").foregroundStyle(.secondary)
                    Sparkline(values: coordinator.history[.diskWrite]?.values ?? [], tint: .orange)
                    StatRow("Read since boot", Format.bytes(disk.totalReadBytes))
                    StatRow("Written since boot", Format.bytes(disk.totalWriteBytes))
                    ForEach(volumes) { volume in
                        StatRow(volume.mountPath, volume.isInternal ? "internal" : "external")
                    }
                }
            }
        }
    }
}
