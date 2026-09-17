import NerdStatsCore
import SwiftUI

/// Nerd mode's per-app list of live sockets, inside the Network section.
struct ConnectionsView: View {
    static let maxProcesses = 25
    static let maxConnectionsPerProcess = 20

    let reading: ConnectionReading?

    @State private var query = ""
    @State private var expanded: Set<Int32> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Connections").foregroundStyle(.secondary)
                Spacer()
                if let reading {
                    Text("\(reading.connectionCount) sockets in \(reading.processes.count) apps")
                        .foregroundStyle(.secondary)
                }
            }
            TextField("Filter by app, host, IP, port or state", text: $query)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            if let reading {
                list(for: reading)
                footnote(for: reading)
            } else {
                Text("Collecting…").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func list(for reading: ConnectionReading) -> some View {
        let filtered = ConnectionList.filter(reading.processes, query: query)
        let limited = ConnectionList.limit(filtered, maxProcesses: Self.maxProcesses,
                                           maxConnections: Self.maxConnectionsPerProcess)
        if filtered.isEmpty {
            Text(query.isEmpty ? "No open connections" : "No matches").foregroundStyle(.secondary)
        }
        ForEach(limited.processes) { process in
            // Searching shows every match without having to expand each app.
            let isExpanded = !query.isEmpty || expanded.contains(process.pid)
            VStack(alignment: .leading, spacing: 2) {
                processHeader(process, isExpanded: isExpanded, showsRate: reading.trafficAvailable)
                if isExpanded {
                    ForEach(process.connections) { connection in
                        ConnectionRow(connection: connection, showsRate: reading.trafficAvailable)
                    }
                    if let more = limited.hiddenConnections[process.pid] {
                        Text("+\(more) more").foregroundStyle(.secondary).padding(.leading, 14)
                    }
                }
            }
        }
        if limited.hiddenProcesses > 0 {
            Text("+\(limited.hiddenProcesses) more apps – filter to find them").foregroundStyle(.secondary)
        }
    }

    private func processHeader(_ process: ProcessConnections, isExpanded: Bool, showsRate: Bool) -> some View {
        Button {
            if expanded.contains(process.pid) {
                expanded.remove(process.pid)
            } else {
                expanded.insert(process.pid)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .frame(width: 10)
                Text(process.name).lineLimit(1).truncationMode(.tail)
                Text("\(process.pid) · \(process.connections.count)").foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if showsRate {
                    Text("↓\(Format.rate(process.downloadBytesPerSecond)) ↑\(Format.rate(process.uploadBytesPerSecond))")
                        .monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("PID \(process.pid), \(process.connections.count) sockets")
    }

    @ViewBuilder
    private func footnote(for reading: ConnectionReading) -> some View {
        if reading.hiddenProcessCount > 0 {
            Text("\(reading.hiddenProcessCount) processes owned by other users (e.g. system services) can't be listed without admin rights.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !reading.trafficAvailable {
            Text("Per-connection speed isn't available on this Mac.").foregroundStyle(.secondary)
        }
    }
}

private struct ConnectionRow: View {
    let connection: NetworkConnection
    let showsRate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(ConnectionText.peer(connection))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                if showsRate, connection.remote != nil {
                    Text("↓\(Format.rate(connection.downloadBytesPerSecond)) ↑\(Format.rate(connection.uploadBytesPerSecond))")
                        .monospacedDigit()
                }
            }
            HStack {
                Text(ConnectionText.details(connection))
                if let address = ConnectionText.address(connection) {
                    Spacer(minLength: 4)
                    Text(address).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 14)
    }
}
