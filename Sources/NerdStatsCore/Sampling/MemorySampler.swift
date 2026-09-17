import Darwin

/// Memory breakdown from Mach VM statistics, plus swap and pressure from sysctl.
public final class MemorySampler: Sampler {
    public init() {}

    public func sample() -> MemoryReading? {
        guard let stats = Self.vmStatistics() else { return nil }
        let pageSize = UInt64(vm_kernel_page_size)
        func bytes(_ pages: natural_t) -> UInt64 { UInt64(pages) * pageSize }

        // These groupings match Activity Monitor's Memory tab.
        let app = bytes(stats.internal_page_count) - min(bytes(stats.internal_page_count), bytes(stats.purgeable_count))
        let swap = Sysctl.value("vm.swapusage", as: xsw_usage.self)

        return MemoryReading(
            totalBytes: Sysctl.value("hw.memsize", as: UInt64.self) ?? 0,
            appBytes: app,
            wiredBytes: bytes(stats.wire_count),
            compressedBytes: bytes(stats.compressor_page_count),
            cachedBytes: bytes(stats.external_page_count) + bytes(stats.purgeable_count),
            freeBytes: bytes(stats.free_count),
            swapUsedBytes: swap?.xsu_used ?? 0,
            swapTotalBytes: swap?.xsu_total ?? 0,
            pressure: Self.pressure()
        )
    }

    private static func vmStatistics() -> vm_statistics64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? stats : nil
    }

    /// The kernel's pressure level: 1 = normal, 2 = warning, 4 = critical.
    private static func pressure() -> MemoryPressure {
        switch Sysctl.int("kern.memorystatus_vm_pressure_level") {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return .unknown
        }
    }
}
