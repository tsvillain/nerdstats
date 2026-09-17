import Darwin
import Foundation
import SystemConfiguration

/// Primary interface, local addresses and throughput.
public final class NetworkSampler: Sampler {
    private var downloadRate = CounterRate()
    private var uploadRate = CounterRate()
    private var displayNames: [String: String] = [:]
    /// Interface names seen at the last refresh of `displayNames`.
    private var seenInterfaces: Set<String>?

    public init() {}

    public func sample() -> NetworkReading? {
        let now = monotonicSeconds()
        let primary = Self.primaryInterface()
        let addresses = primary.map(Self.addresses(of:)) ?? (ipv4: nil, ipv6: nil)

        // Throughput is summed over hardware interfaces so it keeps working while the primary
        // interface changes (e.g. Wi-Fi to Ethernet). Virtual interfaces are skipped because
        // VPN tunnels (utun), AirDrop (awdl) and bridges would count the same bytes twice.
        let allCounters = Self.interfaceCounters()
        // Adapters can be plugged in while the app runs (USB Ethernet, tethering, docks).
        if seenInterfaces != Set(allCounters.keys) {
            seenInterfaces = Set(allCounters.keys)
            displayNames = Self.interfaceDisplayNames()
        }
        let counters = allCounters.filter { NetworkInterfaces.isHardware($0.key, knownNames: displayNames.keys) }
        let received = counters.values.reduce(0) { $0 &+ $1.received }
        let sent = counters.values.reduce(0) { $0 &+ $1.sent }

        return NetworkReading(
            primaryInterface: primary,
            interfaceKind: primary.flatMap { displayNames[$0] },
            localIPv4: addresses.ipv4,
            localIPv6: addresses.ipv6,
            downloadBytesPerSecond: downloadRate.update(received, at: now),
            uploadBytesPerSecond: uploadRate.update(sent, at: now),
            totalReceivedBytes: received,
            totalSentBytes: sent
        )
    }

    /// The interface carrying the IPv4 (or IPv6) default route, from the configd dynamic store.
    private static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "NerdStats" as CFString, nil, nil) else { return nil }
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            if let value = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
               let name = value["PrimaryInterface"] as? String {
                return name
            }
        }
        return nil
    }

    /// Maps BSD names to user-facing names, e.g. "en0" → "Wi-Fi".
    private static func interfaceDisplayNames() -> [String: String] {
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        var names: [String: String] = [:]
        for interface in interfaces {
            if let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
               let display = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                names[bsd] = display
            }
        }
        return names
    }

    /// 64-bit byte counters per interface via the NET_RT_IFLIST2 routing sysctl.
    /// (`getifaddrs` only exposes 32-bit counters, which wrap every 4 GiB.)
    ///
    /// For privacy, macOS rounds these counters to 1 KiB for ordinary processes, so very
    /// light traffic shows up as steps of about 1 KB/s.
    private static func interfaceCounters() -> [String: (received: UInt64, sent: UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: (UInt64, UInt64)] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            // The buffer is a sequence of variable-length routing messages.
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2 {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(message.ifm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        result[name] = (message.ifm_data.ifi_ibytes, message.ifm_data.ifi_obytes)
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return result
    }

    private static func addresses(of interface: String) -> (ipv4: String?, ipv6: String?) {
        var ipv4: String?
        var ipv6: String?
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (nil, nil) }
        defer { freeifaddrs(list) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard String(cString: entry.ifa_name) == interface, let address = entry.ifa_addr else { continue }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(cString: host)
            if family == AF_INET, ipv4 == nil {
                ipv4 = text
            } else if family == AF_INET6, ipv6 == nil, !text.hasPrefix("fe80") {
                ipv6 = text // Skip link-local addresses; they are not useful to show.
            }
        }
        return (ipv4, ipv6)
    }
}

enum NetworkInterfaces {
    /// True for interfaces System Settings lists as network hardware (Wi-Fi, Ethernet,
    /// Thunderbolt), excluding bridges that aggregate other interfaces.
    static func isHardware<Names: Sequence>(_ name: String, knownNames: Names) -> Bool where Names.Element == String {
        !name.hasPrefix("bridge") && knownNames.contains(name)
    }
}

/// Looks up the public IP address. Only called when the user explicitly asks, because it
/// contacts an external service.
public enum PublicIPLookup {
    public static let serviceURL = URL(string: "https://api.ipify.org")!

    public static func fetch() async throws -> String {
        var request = URLRequest(url: serviceURL)
        request.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: request)
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 45 else { throw URLError(.badServerResponse) }
        return text
    }
}
