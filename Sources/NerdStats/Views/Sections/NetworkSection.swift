import NerdStatsCore
import SwiftUI

struct NetworkSection: View {
    @EnvironmentObject private var coordinator: StatsCoordinator

    var body: some View {
        let network = coordinator.snapshot.network
        SectionCard(title: "Network", systemImage: "network") {
            if let network {
                VStack(alignment: .leading, spacing: 4) {
                    if let interface = network.primaryInterface {
                        StatRow("Connected via", "\(network.interfaceKind ?? interface) (\(interface))")
                    } else {
                        UnavailableText("Not connected")
                    }
                    StatRow("↓ Download", Format.rate(network.downloadBytesPerSecond))
                    StatRow("↑ Upload", Format.rate(network.uploadBytesPerSecond))
                    Sparkline(values: coordinator.history[.download]?.values ?? [], tint: .green)
                }
            } else {
                UnavailableText("Waiting for the first reading…")
            }
        } detail: {
            if let network {
                VStack(alignment: .leading, spacing: 2) {
                    StatRow("Local IPv4", network.localIPv4 ?? "–")
                    StatRow("Local IPv6", network.localIPv6 ?? "–")
                    publicIPRow
                    StatRow("Received since boot", Format.bytes(network.totalReceivedBytes))
                    StatRow("Sent since boot", Format.bytes(network.totalSentBytes))
                    Text("Upload").foregroundStyle(.secondary)
                    Sparkline(values: coordinator.history[.upload]?.values ?? [], tint: .pink)
                }
            }
        }
    }

    /// The public IP is only fetched on request, since it contacts an outside server.
    @ViewBuilder private var publicIPRow: some View {
        HStack {
            Text("Public IP").foregroundStyle(.secondary)
            Spacer()
            switch coordinator.publicIP {
            case .notRequested:
                Button("Look up") { coordinator.fetchPublicIP() }
                    .help("Asks \(PublicIPLookup.serviceURL.host ?? "an external service") for your public address")
            case .loading:
                ProgressView().controlSize(.mini)
            case .loaded(let address):
                Text(address).textSelection(.enabled)
            case .failed:
                Button("Failed – retry") { coordinator.fetchPublicIP() }
            }
        }
    }
}
