import Foundation

// Plain value types produced by the samplers. They carry raw numbers only; formatting and
// status interpretation happen in `Format` and `StatusRules`.

// MARK: - System

public struct SystemInfo: Equatable, Sendable {
    public enum Architecture: String, Sendable {
        case appleSilicon = "Apple Silicon"
        case intel = "Intel"
    }

    /// A group of identical cores, e.g. "Performance" × 4.
    public struct CoreCluster: Equatable, Sendable {
        public var name: String
        public var physicalCores: Int
    }

    public var modelName: String          // "MacBook Air (M1, 2020)" when known
    public var modelIdentifier: String    // "MacBookAir10,1"
    public var chipName: String           // "Apple M1" / "Intel(R) Core(TM) i7-…"
    public var architecture: Architecture
    public var physicalCores: Int
    public var logicalCores: Int
    public var coreClusters: [CoreCluster] // empty on Intel
    public var memoryBytes: UInt64
    public var osVersion: String
    public var hostName: String
    public var bootTime: Date?
    /// True when this x86_64 build is running under Rosetta 2.
    public var isTranslated: Bool

    public var uptime: TimeInterval? { bootTime.map { Date().timeIntervalSince($0) } }
}

// MARK: - CPU

public struct CPUReading: Equatable, Sendable {
    public var total: CPUUsage
    public var perCore: [CPUUsage]
    /// 1, 5 and 15 minute load averages.
    public var loadAverages: [Double]
}

public struct ProcessUsage: Equatable, Sendable, Identifiable {
    public var pid: Int32
    public var name: String
    /// Fraction of one core (1.0 = 100% of a single core, like Activity Monitor).
    public var cpu: Double
    /// Physical memory footprint in bytes.
    public var memoryBytes: UInt64
    public var id: Int32 { pid }
}

public struct ProcessReading: Equatable, Sendable {
    public var topByCPU: [ProcessUsage]
    public var topByMemory: [ProcessUsage]
    /// Processes owned by other users (e.g. root) cannot be inspected without privileges.
    public var inspectedCount: Int
    public var totalCount: Int
}

// MARK: - GPU

public struct GPUReading: Equatable, Sendable, Identifiable {
    /// Position in registry order; names are not unique when a Mac has two identical GPUs.
    public var index: Int
    public var name: String
    /// 0...1, `nil` if the driver does not report it.
    public var utilization: Double?
    public var memoryUsedBytes: UInt64?
    public var memoryTotalBytes: UInt64?
    public var id: Int { index }
}

// MARK: - Memory

public enum MemoryPressure: String, Sendable {
    case normal = "Normal"
    case warning = "Warning"
    case critical = "Critical"
    case unknown = "Unknown"
}

public struct MemoryReading: Equatable, Sendable {
    public var totalBytes: UInt64
    public var appBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    /// File cache and purgeable memory the system can reclaim instantly.
    public var cachedBytes: UInt64
    public var freeBytes: UInt64
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64
    public var pressure: MemoryPressure

    /// "Memory Used" as Activity Monitor defines it: app + wired + compressed.
    public var usedBytes: UInt64 { appBytes + wiredBytes + compressedBytes }
    public var usedFraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
}

// MARK: - Disk

public struct VolumeInfo: Equatable, Sendable, Identifiable {
    public var name: String
    public var mountPath: String
    public var totalBytes: UInt64
    public var availableBytes: UInt64
    public var isInternal: Bool
    public var id: String { mountPath }

    public var usedFraction: Double {
        totalBytes > 0 ? 1 - Double(availableBytes) / Double(totalBytes) : 0
    }
}

public struct DiskReading: Equatable, Sendable {
    public var volumes: [VolumeInfo]
    public var readBytesPerSecond: Double?
    public var writeBytesPerSecond: Double?
    public var totalReadBytes: UInt64
    public var totalWriteBytes: UInt64
}

// MARK: - Network

public struct NetworkReading: Equatable, Sendable {
    /// BSD name of the interface carrying the default route, e.g. "en0".
    public var primaryInterface: String?
    public var interfaceKind: String?
    public var localIPv4: String?
    public var localIPv6: String?
    public var downloadBytesPerSecond: Double?
    public var uploadBytesPerSecond: Double?
    /// Totals across hardware interfaces (Wi-Fi, Ethernet, …) since boot.
    public var totalReceivedBytes: UInt64
    public var totalSentBytes: UInt64
}

// MARK: - Battery & power

public struct PowerReading: Equatable, Sendable {
    public var chargeFraction: Double?
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var isFullyCharged: Bool
    public var minutesToEmpty: Int?
    public var minutesToFull: Int?
    public var cycleCount: Int?
    public var health: Double?
    public var maxCapacitymAh: Int?
    public var designCapacitymAh: Int?
    public var temperatureCelsius: Double?
    public var adapterWatts: Double?
    public var adapterName: String?
    /// Power flowing into (positive, charging) or out of (negative) the battery, in watts.
    public var batteryWatts: Double?
    /// Total system power draw in watts, where the hardware reports it.
    public var systemWatts: Double?
    public var voltage: Double?
}

// MARK: - Sensors

public struct TemperatureSensor: Equatable, Sendable, Identifiable {
    public enum Category: String, Sendable, CaseIterable {
        case cpu = "CPU"
        case gpu = "GPU"
        case soc = "SoC"
        case battery = "Battery"
        case storage = "Storage"
        case other = "Other"
    }

    public var name: String
    public var category: Category
    public var celsius: Double
    /// "HID" or "SMC", to show where a value came from in Nerd mode.
    public var source: String
    public var id: String { source + ":" + name }
}

public struct FanReading: Equatable, Sendable, Identifiable {
    public var index: Int
    public var rpm: Double
    public var minRPM: Double?
    public var maxRPM: Double?
    public var id: Int { index }
}

public struct SensorReading: Equatable, Sendable {
    public var temperatures: [TemperatureSensor]
    public var fans: [FanReading]

    public static let empty = SensorReading(temperatures: [], fans: [])

    /// Hottest CPU sensor, falling back to the hottest SoC sensor on chips without
    /// per-cluster sensors. (Averaging would mix in cooler board sensors near the die.)
    public var cpuCelsius: Double? {
        hottest(.cpu) ?? hottest(.soc)
    }

    public var gpuCelsius: Double? { hottest(.gpu) }
    public var batteryCelsius: Double? { average(.battery) }

    public func hottest(_ category: TemperatureSensor.Category) -> Double? {
        temperatures.filter { $0.category == category }.map(\.celsius).max()
    }

    public func average(_ category: TemperatureSensor.Category) -> Double? {
        let values = temperatures.filter { $0.category == category }.map(\.celsius)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - Network connections

public enum TransportProtocol: String, Sendable {
    case tcp = "TCP"
    case udp = "UDP"
}

/// TCP connection states, numbered as in the kernel's `tcp_fsm.h`.
public enum TCPState: Int32, Sendable {
    case closed = 0, listen, synSent, synReceived, established, closeWait, finWait1, closing, lastAck, finWait2, timeWait

    public var title: String {
        switch self {
        case .closed: return "Closed"
        case .listen: return "Listen"
        case .synSent: return "SYN sent"
        case .synReceived: return "SYN received"
        case .established: return "Established"
        case .closeWait: return "Close wait"
        case .finWait1: return "FIN wait 1"
        case .closing: return "Closing"
        case .lastAck: return "Last ACK"
        case .finWait2: return "FIN wait 2"
        case .timeWait: return "Time wait"
        }
    }
}

/// Which IP versions a socket uses, as `netstat` labels them ("tcp4", "tcp6", "tcp46").
public enum IPVersion: String, Sendable {
    case v4 = "4"
    case v6 = "6"
    case dual = "46"
}

/// One end of a socket. A `nil` address is the wildcard (any address).
public struct SocketEndpoint: Hashable, Sendable {
    public var address: String?
    public var port: UInt16

    public init(address: String?, port: UInt16) {
        self.address = address
        self.port = port
    }
}

public struct NetworkConnection: Equatable, Sendable, Identifiable {
    public var pid: Int32
    public var transport: TransportProtocol
    public var ipVersion: IPVersion
    public var local: SocketEndpoint
    /// `nil` for listening TCP sockets and unconnected UDP sockets.
    public var remote: SocketEndpoint?
    /// `nil` for UDP.
    public var tcpState: TCPState?
    /// Reverse DNS name of the remote address, once resolved.
    public var remoteHostName: String?
    public var downloadBytesPerSecond: Double?
    public var uploadBytesPerSecond: Double?
    /// File descriptor, which keeps sockets with identical endpoints apart.
    public var fileDescriptor: Int32

    public init(pid: Int32, transport: TransportProtocol, ipVersion: IPVersion = .v4, local: SocketEndpoint, remote: SocketEndpoint?,
                tcpState: TCPState?, remoteHostName: String? = nil,
                downloadBytesPerSecond: Double? = nil, uploadBytesPerSecond: Double? = nil, fileDescriptor: Int32 = 0) {
        self.pid = pid
        self.transport = transport
        self.ipVersion = ipVersion
        self.local = local
        self.remote = remote
        self.tcpState = tcpState
        self.remoteHostName = remoteHostName
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.fileDescriptor = fileDescriptor
    }

    public var id: String { "\(pid):\(fileDescriptor):\(ConnectionKey(self).description)" }
}

/// All sockets owned by one process.
public struct ProcessConnections: Equatable, Sendable, Identifiable {
    public var pid: Int32
    public var name: String
    public var connections: [NetworkConnection]
    /// Throughput of every socket the process owns, `nil` where it cannot be measured.
    public var downloadBytesPerSecond: Double?
    public var uploadBytesPerSecond: Double?
    public var id: Int32 { pid }

    public init(pid: Int32, name: String, connections: [NetworkConnection],
                downloadBytesPerSecond: Double? = nil, uploadBytesPerSecond: Double? = nil) {
        self.pid = pid
        self.name = name
        self.connections = connections
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }

    public var totalBytesPerSecond: Double { (downloadBytesPerSecond ?? 0) + (uploadBytesPerSecond ?? 0) }
}

public struct ConnectionReading: Equatable, Sendable {
    /// Processes with at least one internet socket, busiest first.
    public var processes: [ProcessConnections]
    /// Processes whose sockets cannot be listed without root (e.g. system daemons).
    public var hiddenProcessCount: Int
    /// False when per-connection throughput is unavailable on this Mac.
    public var trafficAvailable: Bool

    public var connectionCount: Int { processes.reduce(0) { $0 + $1.connections.count } }
}
