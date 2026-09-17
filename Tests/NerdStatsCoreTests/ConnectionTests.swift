@testable import NerdStatsCore
import XCTest

final class SocketAddressFormatTests: XCTestCase {
    func testIPv4() {
        XCTAssertEqual(SocketAddressFormat.ipv4([192, 168, 1, 20]), "192.168.1.20")
        XCTAssertNil(SocketAddressFormat.ipv4([0, 0, 0, 0]), "all zeros is the wildcard address")
        XCTAssertNil(SocketAddressFormat.ipv4([1, 2, 3]))
    }

    func testIPv6IsCompressed() {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = 0x20; bytes[1] = 0x01; bytes[2] = 0x0d; bytes[3] = 0xb8; bytes[15] = 1
        XCTAssertEqual(SocketAddressFormat.ipv6(bytes), "2001:db8::1")
        XCTAssertNil(SocketAddressFormat.ipv6([UInt8](repeating: 0, count: 16)))
    }

    func testIPv4MappedIPv6ShowsAsIPv4() {
        let bytes: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 17, 253, 144, 10]
        XCTAssertEqual(SocketAddressFormat.ipv6(bytes), "17.253.144.10")
    }

    func testLinkLocalDropsEmbeddedInterfaceIndex() {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = 0xfe; bytes[1] = 0x80; bytes[3] = 0x14; bytes[15] = 1
        XCTAssertEqual(SocketAddressFormat.ipv6(bytes), "fe80::1")
    }

    func testParsesSockaddrIn() {
        // len 16, AF_INET, port 443, 1.2.3.4, 8 bytes of padding
        let bytes: [UInt8] = [16, 2, 0x01, 0xbb, 1, 2, 3, 4, 0, 0, 0, 0, 0, 0, 0, 0]
        XCTAssertEqual(SocketAddressFormat.endpoint(sockaddr: bytes), SocketEndpoint(address: "1.2.3.4", port: 443))
    }

    func testParsesSockaddrIn6() {
        var bytes: [UInt8] = [28, 30, 0x00, 0x35, 0, 0, 0, 0]
        bytes += [0x20, 0x01, 0x0d, 0xb8] + [UInt8](repeating: 0, count: 11) + [2]
        bytes += [0, 0, 0, 0]
        XCTAssertEqual(SocketAddressFormat.endpoint(sockaddr: bytes), SocketEndpoint(address: "2001:db8::2", port: 53))
        XCTAssertNil(SocketAddressFormat.endpoint(sockaddr: [16, 1, 0, 0]), "not an internet address")
        XCTAssertNil(SocketAddressFormat.endpoint(sockaddr: []))
    }

    func testEndpointText() {
        XCTAssertEqual(SocketAddressFormat.text(SocketEndpoint(address: "1.2.3.4", port: 80)), "1.2.3.4:80")
        XCTAssertEqual(SocketAddressFormat.text(SocketEndpoint(address: "::1", port: 80)), "[::1]:80")
        XCTAssertEqual(SocketAddressFormat.text(SocketEndpoint(address: nil, port: 22)), "*:22")
    }
}

final class PortServicesTests: XCTestCase {
    func testWellKnownPorts() {
        XCTAssertEqual(PortServices.name(for: 443, transport: .tcp), "https")
        XCTAssertEqual(PortServices.name(for: 443, transport: .udp), "quic")
        XCTAssertEqual(PortServices.name(for: 53, transport: .udp), "dns")
        XCTAssertNil(PortServices.name(for: 51234, transport: .tcp))
        XCTAssertEqual(PortServices.label(for: 22, transport: .tcp), "22 (ssh)")
        XCTAssertEqual(PortServices.label(for: 51234, transport: .tcp), "51234")
    }
}

final class ConnectionTextTests: XCTestCase {
    func testPeerPrefersHostName() {
        var connection = NetworkConnection(pid: 1, transport: .tcp, local: SocketEndpoint(address: "10.0.0.2", port: 50000),
                                           remote: SocketEndpoint(address: "17.1.1.1", port: 443), tcpState: .established)
        XCTAssertEqual(ConnectionText.peer(connection), "17.1.1.1:443 (https)")
        XCTAssertNil(ConnectionText.address(connection))
        connection.remoteHostName = "apple.com"
        XCTAssertEqual(ConnectionText.peer(connection), "apple.com:443 (https)")
        XCTAssertEqual(ConnectionText.address(connection), "17.1.1.1")
        XCTAssertEqual(ConnectionText.details(connection), "TCP4 · Established · local port 50000")
    }

    func testListeningAndUnconnectedSockets() {
        let listener = NetworkConnection(pid: 1, transport: .tcp, ipVersion: .dual, local: SocketEndpoint(address: nil, port: 22),
                                         remote: nil, tcpState: .listen)
        XCTAssertEqual(ConnectionText.peer(listener), "Listening on *:22 (ssh)")
        XCTAssertEqual(ConnectionText.details(listener), "TCP46 · Listen")
        let udp = NetworkConnection(pid: 1, transport: .udp, local: SocketEndpoint(address: nil, port: 5353),
                                    remote: nil, tcpState: nil)
        XCTAssertEqual(ConnectionText.peer(udp), "Unconnected on *:5353 (mdns)")
    }
}

final class TrafficRatesTests: XCTestCase {
    private let key = ConnectionKey(transport: .tcp, local: SocketEndpoint(address: "10.0.0.2", port: 50000),
                                    remote: SocketEndpoint(address: "1.1.1.1", port: 443))
    private let otherKey = ConnectionKey(transport: .udp, local: SocketEndpoint(address: nil, port: 5353), remote: nil)

    func testKeyTreatsWildcardPortZeroAsNoPeer() {
        XCTAssertNil(ConnectionKey(transport: .udp, local: SocketEndpoint(address: nil, port: 1),
                                   remote: SocketEndpoint(address: nil, port: 0)).remote)
    }

    func testRatesPerConnectionAndProcess() {
        var rates = TrafficRates()
        let first = rates.update([
            TrafficSample(sourceID: 1, pid: 10, key: key, receivedBytes: 1_000, sentBytes: 100),
            TrafficSample(sourceID: 2, pid: 10, key: otherKey, receivedBytes: 0, sentBytes: 0),
        ], at: 0)
        XCTAssertTrue(first.byConnection.isEmpty, "the first reading only sets a baseline")

        let second = rates.update([
            TrafficSample(sourceID: 1, pid: 10, key: key, receivedBytes: 5_000, sentBytes: 300),
            TrafficSample(sourceID: 2, pid: 10, key: otherKey, receivedBytes: 200, sentBytes: 0),
        ], at: 2)
        XCTAssertEqual(second.byConnection[10]?[key], TrafficRate(download: 2_000, upload: 100))
        XCTAssertEqual(second.byConnection[10]?[otherKey], TrafficRate(download: 100, upload: 0))
        XCTAssertEqual(second.byProcess[10], TrafficRate(download: 2_100, upload: 100))
    }

    func testSameEndpointsInDifferentProcessesStaySeparate() {
        var rates = TrafficRates()
        rates.update([
            TrafficSample(sourceID: 1, pid: 10, key: otherKey, receivedBytes: 0, sentBytes: 0),
            TrafficSample(sourceID: 2, pid: 20, key: otherKey, receivedBytes: 0, sentBytes: 0),
        ], at: 0)
        let result = rates.update([
            TrafficSample(sourceID: 1, pid: 10, key: otherKey, receivedBytes: 100, sentBytes: 0),
            TrafficSample(sourceID: 2, pid: 20, key: otherKey, receivedBytes: 0, sentBytes: 40),
        ], at: 1)
        XCTAssertEqual(result.byConnection[10]?[otherKey], TrafficRate(download: 100, upload: 0))
        XCTAssertEqual(result.byConnection[20]?[otherKey], TrafficRate(download: 0, upload: 40))
    }

    func testNewSocketsAreBaselinedNotSpikes() {
        var rates = TrafficRates()
        rates.update([], at: 0)
        let result = rates.update([TrafficSample(sourceID: 7, pid: 3, key: key, receivedBytes: 9_000_000_000, sentBytes: 0)], at: 1)
        XCTAssertNil(result.byConnection[3]?[key])
        XCTAssertEqual(result.byProcess[3], nil)
    }

    func testStaleBaselineAndCounterResets() {
        var rates = TrafficRates(maxInterval: 30)
        rates.update([TrafficSample(sourceID: 1, pid: 1, key: key, receivedBytes: 100, sentBytes: 0)], at: 0)
        XCTAssertTrue(rates.update([TrafficSample(sourceID: 1, pid: 1, key: key, receivedBytes: 200, sentBytes: 0)], at: 60)
            .byConnection.isEmpty)
        let reset = rates.update([TrafficSample(sourceID: 1, pid: 1, key: key, receivedBytes: 50, sentBytes: 0)], at: 61)
        XCTAssertEqual(reset.byConnection[1]?[key], TrafficRate(download: 0, upload: 0), "a counter going backwards is not negative traffic")
    }
}

final class ConnectionListTests: XCTestCase {
    private func socket(_ pid: Int32, remote: String?, port: UInt16 = 443, host: String? = nil,
                        state: TCPState? = .established, rate: Double? = nil, fd: Int32 = 0) -> NetworkConnection {
        NetworkConnection(pid: pid, transport: .tcp, local: SocketEndpoint(address: "10.0.0.2", port: 50_000 + UInt16(fd)),
                          remote: remote.map { SocketEndpoint(address: $0, port: port) }, tcpState: state,
                          remoteHostName: host, downloadBytesPerSecond: rate, fileDescriptor: fd)
    }

    func testGroupsByProcessBusiestFirst() {
        let connections = [
            socket(1, remote: "1.1.1.1", fd: 1),
            socket(2, remote: "2.2.2.2", fd: 1),
            socket(2, remote: "3.3.3.3", fd: 2),
            socket(3, remote: "4.4.4.4", fd: 1),
        ]
        let groups = ConnectionList.group(connections, names: [1: "Safari", 2: "Mail", 3: "zsh"],
                                          processRates: [3: TrafficRate(download: 500, upload: 0)])
        XCTAssertEqual(groups.map(\.name), ["zsh", "Mail", "Safari"], "by speed, then connection count")
        XCTAssertEqual(groups[1].connections.count, 2)
        XCTAssertEqual(groups[0].downloadBytesPerSecond, 500)
        XCTAssertNil(groups[1].downloadBytesPerSecond)
        XCTAssertEqual(ConnectionList.group([socket(9, remote: nil)], names: [:], processRates: [:]).first?.name, "pid 9")
    }

    func testConnectedAndBusySocketsSortFirst() {
        let sorted = ConnectionList.sort([
            socket(1, remote: nil, state: .listen, fd: 1),
            socket(1, remote: "9.9.9.9", fd: 2),
            socket(1, remote: "1.1.1.1", fd: 3),
            socket(1, remote: "5.5.5.5", rate: 10, fd: 4),
        ])
        XCTAssertEqual(sorted.map(\.fileDescriptor), [4, 3, 2, 1])
    }

    func testFilterByProcessKeepsAllSockets() {
        let groups = ConnectionList.group([socket(1, remote: "1.1.1.1", fd: 1), socket(1, remote: "2.2.2.2", fd: 2)],
                                          names: [1: "Safari"], processRates: [:])
        XCTAssertEqual(ConnectionList.filter(groups, query: "safa").first?.connections.count, 2)
        XCTAssertEqual(ConnectionList.filter(groups, query: "1").first?.connections.count, 2, "exact PID match")
        XCTAssertEqual(ConnectionList.filter(groups, query: "  ").count, 1)
    }

    func testFilterByHostAddressPortAndService() {
        let groups = ConnectionList.group([
            socket(1, remote: "17.1.1.1", host: "apple.com", fd: 1),
            socket(1, remote: "8.8.8.8", port: 53, fd: 2),
        ], names: [1: "Safari"], processRates: [:])
        XCTAssertEqual(ConnectionList.filter(groups, query: "APPLE").first?.connections.map(\.fileDescriptor), [1])
        XCTAssertEqual(ConnectionList.filter(groups, query: "8.8.8").first?.connections.map(\.fileDescriptor), [2])
        XCTAssertEqual(ConnectionList.filter(groups, query: "dns").first?.connections.map(\.fileDescriptor), [2])
        XCTAssertEqual(ConnectionList.filter(groups, query: "https").first?.connections.map(\.fileDescriptor), [1])
        XCTAssertTrue(ConnectionList.filter(groups, query: "nothing-matches").isEmpty)
    }

    func testLimit() {
        let groups = (1...5).map { pid in
            ProcessConnections(pid: Int32(pid), name: "p\(pid)",
                               connections: (1...Int32(pid)).map { socket(Int32(pid), remote: "1.1.1.1", fd: $0) })
        }
        let limited = ConnectionList.limit(groups, maxProcesses: 3, maxConnections: 2)
        XCTAssertEqual(limited.processes.map(\.pid), [1, 2, 3])
        XCTAssertEqual(limited.processes.map(\.connections.count), [1, 2, 2])
        XCTAssertEqual(limited.hiddenConnections, [3: 1])
        XCTAssertEqual(limited.hiddenProcesses, 2)
    }
}
