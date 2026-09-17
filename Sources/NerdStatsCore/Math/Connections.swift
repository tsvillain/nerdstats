import Foundation

/// Identifies a socket by protocol and endpoints, so sockets listed through libproc can be
/// matched with the byte counters NetworkStatistics reports for the same socket.
public struct ConnectionKey: Hashable, Sendable, CustomStringConvertible {
    public var transport: TransportProtocol
    public var local: SocketEndpoint
    public var remote: SocketEndpoint?

    public init(transport: TransportProtocol, local: SocketEndpoint, remote: SocketEndpoint?) {
        self.transport = transport
        self.local = local
        // An unconnected socket reports port 0 on the wildcard address; treat it as no peer.
        self.remote = remote.flatMap { $0.address == nil && $0.port == 0 ? nil : $0 }
    }

    public init(_ connection: NetworkConnection) {
        self.init(transport: connection.transport, local: connection.local, remote: connection.remote)
    }

    public var description: String {
        "\(transport.rawValue) \(SocketAddressFormat.text(local)) → \(remote.map(SocketAddressFormat.text) ?? "*")"
    }
}

/// One socket's byte counters, as reported by NetworkStatistics.
public struct TrafficSample: Equatable, Sendable {
    public var sourceID: UInt64
    public var pid: Int32
    public var key: ConnectionKey
    public var receivedBytes: UInt64
    public var sentBytes: UInt64

    public init(sourceID: UInt64, pid: Int32, key: ConnectionKey, receivedBytes: UInt64, sentBytes: UInt64) {
        self.sourceID = sourceID
        self.pid = pid
        self.key = key
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
    }
}

/// Download and upload speed in bytes per second.
public struct TrafficRate: Equatable, Sendable {
    public var download: Double
    public var upload: Double

    public init(download: Double, upload: Double) {
        self.download = download
        self.upload = upload
    }
}

/// Turns per-socket byte counters into speeds per connection and per process.
///
/// Sockets come and go between samples, so per-process speed is the sum of each socket's
/// growth rather than the difference of two totals (which would drop when a busy socket closes).
public struct TrafficRates: Sendable {
    public let maxInterval: TimeInterval
    private var lastBytes: [UInt64: (received: UInt64, sent: UInt64)] = [:]
    private var lastTime: TimeInterval?

    public init(maxInterval: TimeInterval = 30) {
        self.maxInterval = maxInterval
    }

    public mutating func update(_ samples: [TrafficSample], at time: TimeInterval)
        -> (byConnection: [ConnectionKey: TrafficRate], byProcess: [Int32: TrafficRate]) {
        let previous = lastBytes
        let previousTime = lastTime
        lastBytes = Dictionary(samples.map { ($0.sourceID, ($0.receivedBytes, $0.sentBytes)) }, uniquingKeysWith: { $1 })
        lastTime = time

        // The first reading, or one after a long pause, only sets the baseline.
        guard let previousTime, time > previousTime, time - previousTime <= maxInterval else { return ([:], [:]) }
        let elapsed = time - previousTime

        var byConnection: [ConnectionKey: TrafficRate] = [:]
        var byProcess: [Int32: TrafficRate] = [:]
        for sample in samples {
            // A socket first seen now may be long-lived (the monitor reports existing sockets
            // gradually), so its bytes so far only set a baseline instead of showing as a spike.
            guard let before = previous[sample.sourceID] else { continue }
            let received = sample.receivedBytes >= before.received ? sample.receivedBytes - before.received : 0
            let sent = sample.sentBytes >= before.sent ? sample.sentBytes - before.sent : 0
            let rate = TrafficRate(download: Double(received) / elapsed, upload: Double(sent) / elapsed)
            byConnection[sample.key, default: TrafficRate(download: 0, upload: 0)].add(rate)
            byProcess[sample.pid, default: TrafficRate(download: 0, upload: 0)].add(rate)
        }
        return (byConnection, byProcess)
    }
}

private extension TrafficRate {
    mutating func add(_ other: TrafficRate) {
        download += other.download
        upload += other.upload
    }
}

/// Pure grouping, ordering, searching and trimming of connection lists.
public enum ConnectionList {
    /// Groups sockets by process, busiest process first, then by connection count and name.
    public static func group(_ connections: [NetworkConnection], names: [Int32: String],
                             processRates: [Int32: TrafficRate]) -> [ProcessConnections] {
        Dictionary(grouping: connections, by: \.pid).map { pid, sockets in
            let rate = processRates[pid]
            return ProcessConnections(pid: pid, name: names[pid] ?? "pid \(pid)", connections: sort(sockets),
                                      downloadBytesPerSecond: rate?.download, uploadBytesPerSecond: rate?.upload)
        }
        .sorted { lhs, rhs in
            if lhs.totalBytesPerSecond != rhs.totalBytesPerSecond { return lhs.totalBytesPerSecond > rhs.totalBytesPerSecond }
            if lhs.connections.count != rhs.connections.count { return lhs.connections.count > rhs.connections.count }
            if lhs.name != rhs.name { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
            return lhs.pid < rhs.pid
        }
    }

    /// Busiest first, then connected sockets before listening/unconnected ones.
    static func sort(_ connections: [NetworkConnection]) -> [NetworkConnection] {
        connections.sorted { lhs, rhs in
            let lhsRate = (lhs.downloadBytesPerSecond ?? 0) + (lhs.uploadBytesPerSecond ?? 0)
            let rhsRate = (rhs.downloadBytesPerSecond ?? 0) + (rhs.uploadBytesPerSecond ?? 0)
            if lhsRate != rhsRate { return lhsRate > rhsRate }
            if (lhs.remote != nil) != (rhs.remote != nil) { return lhs.remote != nil }
            let lhsName = lhs.remoteHostName ?? lhs.remote?.address ?? ""
            let rhsName = rhs.remoteHostName ?? rhs.remote?.address ?? ""
            if lhsName != rhsName { return lhsName < rhsName }
            return lhs.local.port < rhs.local.port
        }
    }

    /// Keeps processes whose name or PID matches `query`, and in other processes only the
    /// sockets whose host, address, port, service, protocol or state matches. Case-insensitive.
    public static func filter(_ processes: [ProcessConnections], query: String) -> [ProcessConnections] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return processes }
        return processes.compactMap { process in
            if process.name.lowercased().contains(needle) || String(process.pid) == needle { return process }
            var matching = process
            matching.connections = process.connections.filter { matches($0, needle) }
            return matching.connections.isEmpty ? nil : matching
        }
    }

    private static func matches(_ connection: NetworkConnection, _ needle: String) -> Bool {
        var fields = [connection.transport.rawValue, String(connection.local.port)]
        if let state = connection.tcpState { fields.append(state.title) }
        if let host = connection.remoteHostName { fields.append(host) }
        if let remote = connection.remote {
            fields.append(String(remote.port))
            if let address = remote.address { fields.append(address) }
            if let service = PortServices.name(for: remote.port, transport: connection.transport) { fields.append(service) }
        }
        return fields.contains { $0.lowercased().contains(needle) }
    }

    /// At most `maxProcesses` groups with at most `maxConnections` sockets each. Returns how
    /// many sockets were cut from each group so the UI can say "+N more".
    public static func limit(_ processes: [ProcessConnections], maxProcesses: Int, maxConnections: Int)
        -> (processes: [ProcessConnections], hiddenConnections: [Int32: Int], hiddenProcesses: Int) {
        var hidden: [Int32: Int] = [:]
        let kept = processes.prefix(maxProcesses).map { process -> ProcessConnections in
            guard process.connections.count > maxConnections else { return process }
            var trimmed = process
            trimmed.connections = Array(process.connections.prefix(maxConnections))
            hidden[process.pid] = process.connections.count - maxConnections
            return trimmed
        }
        return (kept, hidden, max(0, processes.count - maxProcesses))
    }
}
