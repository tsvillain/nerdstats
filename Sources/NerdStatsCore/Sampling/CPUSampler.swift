import Darwin

/// Total and per-core CPU usage from the Mach host's per-processor tick counters.
public final class CPUSampler: Sampler {
    private var previousTicks: [CPUTicks] = []

    public init() {}

    public func sample() -> CPUReading? {
        guard let ticks = Self.readPerCoreTicks() else { return nil }
        defer { previousTicks = ticks }

        let perCore: [CPUUsage]
        let total: CPUUsage
        if previousTicks.count == ticks.count {
            perCore = zip(previousTicks, ticks).map { CPUUsage(from: $0, to: $1) ?? .idle }
            let previousSum = previousTicks.reduce(CPUTicks.zero, +)
            let currentSum = ticks.reduce(CPUTicks.zero, +)
            total = CPUUsage(from: previousSum, to: currentSum) ?? .idle
        } else {
            // First sample (or core count changed): no interval to measure yet.
            perCore = Array(repeating: .idle, count: ticks.count)
            total = .idle
        }

        var loads = [Double](repeating: 0, count: 3)
        let loadCount = getloadavg(&loads, 3)
        return CPUReading(total: total, perCore: perCore, loadAverages: loadCount == 3 ? loads : [])
    }

    /// `host_processor_info` returns a kernel-allocated array of `processor_cpu_load_info`
    /// (four `UInt32` tick counters per core) that the caller must `vm_deallocate`.
    private static func readPerCoreTicks() -> [CPUTicks]? {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        let stateCount = Int(CPU_STATE_MAX)
        return (0..<Int(coreCount)).map { core in
            // Counters are unsigned 32-bit values stored in a signed array.
            func ticks(_ state: Int32) -> UInt64 {
                UInt64(UInt32(bitPattern: info[core * stateCount + Int(state)]))
            }
            return CPUTicks(user: ticks(CPU_STATE_USER), system: ticks(CPU_STATE_SYSTEM),
                            idle: ticks(CPU_STATE_IDLE), nice: ticks(CPU_STATE_NICE))
        }
    }
}
