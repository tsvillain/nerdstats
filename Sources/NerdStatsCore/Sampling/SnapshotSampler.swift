import Foundation

/// The subsystems a caller can ask `SnapshotSampler` to refresh.
public enum Subsystem: CaseIterable, Sendable {
    case system, cpu, processes, gpu, memory, disk, network, power
    /// Every temperature sensor and fan.
    case sensors
    /// Only the processor temperature: a cheap subset of `sensors` for the menu bar.
    case processorTemperature
    /// Per-process sockets. Costlier than the rest, so only sampled while Nerd mode shows them.
    case connections
}

/// Latest reading from every subsystem. Fields stay `nil` until first sampled, or when
/// the hardware does not exist (e.g. `power` on a desktop Mac).
public struct SystemSnapshot: Equatable, Sendable {
    public var system: SystemInfo?
    public var cpu: CPUReading?
    public var processes: ProcessReading?
    public var gpus: [GPUReading]?
    public var memory: MemoryReading?
    public var disk: DiskReading?
    public var network: NetworkReading?
    public var power: PowerReading?
    public var sensors: SensorReading?
    public var connections: ConnectionReading?
    public var timestamp = Date()

    public init() {}
}

/// Owns one sampler per subsystem and merges their readings into a `SystemSnapshot`.
///
/// Not thread-safe: call it from a single serial queue. It is marked `@unchecked Sendable`
/// only so that queue can take ownership of it; it is never used from two threads at once.
public final class SnapshotSampler: @unchecked Sendable {
    private let systemSampler = SystemInfoSampler()
    private let cpuSampler = CPUSampler()
    private let processSampler = ProcessSampler()
    private let gpuSampler = GPUSampler()
    private let memorySampler = MemorySampler()
    private let diskSampler = DiskSampler()
    private let networkSampler = NetworkSampler()
    private let powerSampler = PowerSampler()
    /// Created on first use: opening the SMC and HID clients is only worth it if temperatures are wanted.
    private lazy var sensorSampler = SensorSampler()
    private let connectionSampler = ConnectionSampler()

    private var snapshot = SystemSnapshot()

    public init() {}

    /// Refreshes only `subsystems`, keeping the previous values of the rest.
    public func sample(_ subsystems: Set<Subsystem>) -> SystemSnapshot {
        for subsystem in Subsystem.allCases where subsystems.contains(subsystem) {
            switch subsystem {
            case .system: snapshot.system = systemSampler.sample()
            case .cpu: snapshot.cpu = cpuSampler.sample()
            case .processes: snapshot.processes = processSampler.sample()
            case .gpu: snapshot.gpus = gpuSampler.sample()
            case .memory: snapshot.memory = memorySampler.sample()
            case .disk: snapshot.disk = diskSampler.sample()
            case .network: snapshot.network = networkSampler.sample()
            case .power: snapshot.power = powerSampler.sample()
            case .sensors: snapshot.sensors = sensorSampler.sample()
            case .processorTemperature:
                // A full sensor read already includes the processor sensors.
                if !subsystems.contains(.sensors) {
                    snapshot.sensors = sensorSampler.sample(processorOnly: true)
                }
            case .connections: snapshot.connections = connectionSampler.sample()
            }
        }
        if !subsystems.contains(.connections), snapshot.connections != nil {
            // Release the traffic monitor and drop the list so it is not shown stale later.
            connectionSampler.stop()
            snapshot.connections = nil
        }
        // Newer Macs no longer publish the battery temperature in the registry; use the
        // battery sensor instead when one exists.
        if snapshot.power != nil, snapshot.power?.temperatureCelsius == nil {
            let batteryCelsius = snapshot.sensors?.batteryCelsius
            snapshot.power?.temperatureCelsius = batteryCelsius
        }
        snapshot.timestamp = Date()
        return snapshot
    }
}
