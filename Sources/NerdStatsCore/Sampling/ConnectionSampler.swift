import CNerdStatsPrivate
import Darwin
import Foundation

/// Every process's TCP and UDP sockets, with reverse DNS names and throughput.
///
/// Sockets are listed through libproc (what `lsof` uses), which only works for processes
/// owned by the current user without root; the rest are counted as hidden. Throughput comes
/// from NetworkStatistics (what `nettop` uses) while `sample()` keeps being called; `stop()`
/// releases it. Host names resolve in the background and appear on a later sample.
public final class ConnectionSampler: Sampler {
    private let resolver = HostNameResolver()
    private var trafficMonitor: OpaquePointer?
    private var trafficUnavailable = false
    private var rates = TrafficRates()

    public init() {}

    deinit { stop() }

    public func sample() -> ConnectionReading? {
        let traffic = sampleTraffic()
        var names: [Int32: String] = [:]
        var connections: [NetworkConnection] = []
        var hidden = 0

        for pid in ProcessSampler.allPIDs() where pid > 0 {
            guard let descriptors = Self.socketDescriptors(of: pid) else {
                hidden += 1
                continue
            }
            // Duplicated descriptors (dup, fork) refer to the same socket; list it once.
            var seenSockets: Set<UInt64> = []
            for descriptor in descriptors {
                guard let (socketID, found) = Self.connection(pid: pid, fileDescriptor: descriptor),
                      seenSockets.insert(socketID).inserted else { continue }
                var connection = found
                if let address = connection.remote?.address {
                    connection.remoteHostName = resolver.cachedName(for: address)
                }
                if let rate = traffic?.byConnection[pid]?[ConnectionKey(connection)] {
                    connection.downloadBytesPerSecond = rate.download
                    connection.uploadBytesPerSecond = rate.upload
                }
                connections.append(connection)
            }
            if connections.last?.pid == pid {
                names[pid] = ProcessSampler.name(of: pid)
            }
        }

        return ConnectionReading(
            processes: ConnectionList.group(connections, names: names, processRates: traffic?.byProcess ?? [:]),
            hiddenProcessCount: hidden,
            trafficAvailable: traffic != nil
        )
    }

    /// Releases the traffic monitor and pending lookups while connections are not shown.
    public func stop() {
        if let monitor = trafficMonitor {
            NerdStatsTrafficMonitorDestroy(monitor)
            trafficMonitor = nil
        }
        rates = TrafficRates()
        resolver.cancelPending()
    }

    private func sampleTraffic() -> (byConnection: [Int32: [ConnectionKey: TrafficRate]], byProcess: [Int32: TrafficRate])? {
        if trafficMonitor == nil, !trafficUnavailable {
            trafficMonitor = NerdStatsTrafficMonitorCreate()
            trafficUnavailable = trafficMonitor == nil
        }
        guard let monitor = trafficMonitor else { return nil }

        var samples: [TrafficSample] = []
        withUnsafeMutablePointer(to: &samples) { pointer in
            _ = NerdStatsTrafficMonitorQuery(monitor, 0.5, pointer) { context, sourceID, pid, isTCP, local, localLength, remote, remoteLength, received, sent in
                guard let context,
                      let localEndpoint = SocketAddressFormat.endpoint(sockaddr: ConnectionSampler.bytes(local, localLength)) else { return }
                let key = ConnectionKey(transport: isTCP ? .tcp : .udp, local: localEndpoint,
                                        remote: SocketAddressFormat.endpoint(sockaddr: ConnectionSampler.bytes(remote, remoteLength)))
                context.assumingMemoryBound(to: [TrafficSample].self).pointee.append(
                    TrafficSample(sourceID: sourceID, pid: pid, key: key, receivedBytes: received, sentBytes: sent))
            }
        }
        return rates.update(samples, at: monotonicSeconds())
    }

    private static func bytes(_ pointer: UnsafePointer<UInt8>?, _ length: Int) -> [UInt8] {
        guard let pointer, length > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: pointer, count: length))
    }

    /// Socket file descriptors of `pid`, or `nil` if the process cannot be inspected.
    private static func socketDescriptors(of pid: Int32) -> [Int32]? {
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        // A process that exited since it was listed is gone, not hidden.
        guard needed > 0 else { return errno == ESRCH ? [] : nil }
        let stride = MemoryLayout<proc_fdinfo>.stride
        // Leave headroom for descriptors opened between the two calls.
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 16)
        let used = fds.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard used > 0 else { return nil }
        return fds.prefix(Int(used) / stride)
            .filter { $0.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) }
            .map(\.proc_fd)
    }

    /// The socket behind a descriptor, with the kernel's (per-boot obfuscated) socket identity.
    private static func connection(pid: Int32, fileDescriptor: Int32) -> (UInt64, NetworkConnection)? {
        var info = socket_fdinfo()
        let size = Int32(MemoryLayout<socket_fdinfo>.size)
        guard proc_pidfdinfo(pid, fileDescriptor, PROC_PIDFDSOCKETINFO, &info, size) == size else { return nil }
        let socket = info.psi
        guard socket.soi_family == AF_INET || socket.soi_family == AF_INET6 else { return nil }

        let transport: TransportProtocol
        let internet: in_sockinfo
        var state: TCPState?
        switch socket.soi_kind {
        case Int32(SOCKINFO_TCP):
            transport = .tcp
            internet = socket.soi_proto.pri_tcp.tcpsi_ini
            state = TCPState(rawValue: socket.soi_proto.pri_tcp.tcpsi_state)
        case Int32(SOCKINFO_IN) where socket.soi_protocol == IPPROTO_UDP:
            transport = .udp
            internet = socket.soi_proto.pri_in
        default:
            return nil
        }

        let isIPv4 = internet.insi_vflag & UInt8(INI_IPV4) != 0
        let isIPv6 = internet.insi_vflag & UInt8(INI_IPV6) != 0
        let ipVersion: IPVersion = isIPv4 && isIPv6 ? .dual : (isIPv6 ? .v6 : .v4)
        func address(_ value: in_sockinfo.__Unnamed_union_insi_faddr) -> String? {
            var copy = value
            if isIPv4 {
                return withUnsafeBytes(of: &copy.ina_46.i46a_addr4) { SocketAddressFormat.ipv4(Array($0)) }
            }
            return withUnsafeBytes(of: &copy.ina_6) { SocketAddressFormat.ipv6(Array($0)) }
        }
        // Ports are stored in network byte order in the low 16 bits.
        func port(_ value: Int32) -> UInt16 { UInt16(bigEndian: UInt16(truncatingIfNeeded: value)) }

        let local = SocketEndpoint(address: address(unsafeBitCast(internet.insi_laddr, to: in_sockinfo.__Unnamed_union_insi_faddr.self)),
                                   port: port(internet.insi_lport))
        let remote = SocketEndpoint(address: address(internet.insi_faddr), port: port(internet.insi_fport))
        return (socket.soi_so, NetworkConnection(
            pid: pid, transport: transport, ipVersion: ipVersion, local: local,
            remote: ConnectionKey(transport: transport, local: local, remote: remote).remote,
            tcpState: state, fileDescriptor: fileDescriptor))
    }
}
