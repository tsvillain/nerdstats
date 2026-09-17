import Darwin
import Foundation

/// Turns raw socket addresses into display strings.
public enum SocketAddressFormat {
    /// Dotted IPv4 from its four bytes in network order. All zeros (the wildcard) is `nil`.
    public static func ipv4(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 4, bytes.contains(where: { $0 != 0 }) else { return nil }
        return bytes.map(String.init).joined(separator: ".")
    }

    /// Compressed IPv6 from its sixteen bytes. IPv4-mapped addresses (`::ffff:a.b.c.d`),
    /// which dual-stack sockets use, are shown as plain IPv4. All zeros is `nil`.
    public static func ipv6(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 16, bytes.contains(where: { $0 != 0 }) else { return nil }
        if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
            return ipv4(Array(bytes[12..<16]))
        }
        var bytes = bytes
        if bytes[0] == 0xfe, bytes[1] & 0xc0 == 0x80 {
            // The kernel embeds the interface index of link-local addresses in bytes 2-3.
            bytes[2] = 0
            bytes[3] = 0
        }
        var address = in6_addr()
        withUnsafeMutableBytes(of: &address) { $0.copyBytes(from: bytes) }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        return String(cString: buffer)
    }

    /// Parses a raw `sockaddr_in` or `sockaddr_in6` (BSD layout: length, family, port, …).
    public static func endpoint(sockaddr bytes: [UInt8]) -> SocketEndpoint? {
        guard bytes.count >= 4 else { return nil }
        let family = Int32(bytes[1])
        let port = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        switch family {
        case AF_INET where bytes.count >= 8:
            return SocketEndpoint(address: ipv4(Array(bytes[4..<8])), port: port)
        case AF_INET6 where bytes.count >= 24:
            return SocketEndpoint(address: ipv6(Array(bytes[8..<24])), port: port)
        default:
            return nil
        }
    }

    /// "1.2.3.4:443", "[2001:db8::1]:443", or "*:53" for the wildcard address.
    public static func text(_ endpoint: SocketEndpoint) -> String {
        guard let address = endpoint.address else { return "*:\(endpoint.port)" }
        return address.contains(":") ? "[\(address)]:\(endpoint.port)" : "\(address):\(endpoint.port)"
    }
}

/// Names of well-known ports, like a tiny `/etc/services`.
public enum PortServices {
    private static let shared: [UInt16: String] = [
        20: "ftp-data", 21: "ftp", 22: "ssh", 23: "telnet", 25: "smtp", 53: "dns", 67: "dhcp", 68: "dhcp",
        80: "http", 88: "kerberos", 110: "pop3", 123: "ntp", 137: "netbios", 138: "netbios", 139: "netbios",
        143: "imap", 161: "snmp", 389: "ldap", 443: "https", 445: "smb", 465: "smtps", 500: "ike", 514: "syslog",
        548: "afp", 587: "submission", 631: "ipp", 636: "ldaps", 853: "dns-over-tls", 993: "imaps", 995: "pop3s",
        1194: "openvpn", 1433: "mssql", 1900: "ssdp", 3306: "mysql", 3389: "rdp", 4500: "ipsec-nat", 5060: "sip",
        5223: "apns", 5228: "google-push", 5353: "mdns", 5432: "postgresql", 5900: "vnc", 6379: "redis",
        7000: "airplay", 8080: "http-alt", 8443: "https-alt", 27017: "mongodb",
    ]

    /// The service usually found on `port`, or `nil` if it is not a well-known one.
    public static func name(for port: UInt16, transport: TransportProtocol) -> String? {
        // HTTPS over UDP is HTTP/3.
        if port == 443, transport == .udp { return "quic" }
        return shared[port]
    }

    /// "443 (https)" or just "51234".
    public static func label(for port: UInt16, transport: TransportProtocol) -> String {
        name(for: port, transport: transport).map { "\(port) (\($0))" } ?? "\(port)"
    }
}

/// Display text for one socket, shared by the dashboard and `--dump`.
public enum ConnectionText {
    /// "example.com:443 (https)", "[2001:db8::1]:53 (dns)", or "Listening on *:22 (ssh)".
    public static func peer(_ connection: NetworkConnection) -> String {
        guard let remote = connection.remote else {
            let local = portLabel(connection.local, connection)
            return connection.transport == .tcp ? "Listening on \(local)" : "Unconnected on \(local)"
        }
        guard let host = connection.remoteHostName else { return portLabel(remote, connection) }
        return "\(host):\(PortServices.label(for: remote.port, transport: connection.transport))"
    }

    /// The remote IP address when a host name is shown instead of it.
    public static func address(_ connection: NetworkConnection) -> String? {
        guard connection.remoteHostName != nil else { return nil }
        return connection.remote?.address
    }

    /// "TCP4 · Established · local port 54321".
    public static func details(_ connection: NetworkConnection) -> String {
        var parts = [connection.transport.rawValue + connection.ipVersion.rawValue]
        if let state = connection.tcpState { parts.append(state.title) }
        if connection.remote != nil { parts.append("local port \(connection.local.port)") }
        return parts.joined(separator: " · ")
    }

    public static func summary(_ connection: NetworkConnection) -> String {
        var text = peer(connection)
        if let address = address(connection) { text += " [\(address)]" }
        text += " — " + details(connection)
        if connection.downloadBytesPerSecond != nil || connection.uploadBytesPerSecond != nil {
            text += " ↓ \(Format.rate(connection.downloadBytesPerSecond)) ↑ \(Format.rate(connection.uploadBytesPerSecond))"
        }
        return text
    }

    private static func portLabel(_ endpoint: SocketEndpoint, _ connection: NetworkConnection) -> String {
        let text = SocketAddressFormat.text(endpoint)
        guard let service = PortServices.name(for: endpoint.port, transport: connection.transport) else { return text }
        return "\(text) (\(service))"
    }
}
