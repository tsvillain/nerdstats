import Darwin
import Foundation

/// The heaviest processes by CPU and by memory, using libproc (what `top` uses).
///
/// Without elevated privileges only processes owned by the current user can be
/// inspected; others are counted but skipped.
public final class ProcessSampler: Sampler {
    public var limit: Int

    /// CPU time rate per pid, in nanoseconds per second.
    private var cpuRates: [Int32: CounterRate] = [:]
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public init(limit: Int = 5) {
        self.limit = limit
    }

    public func sample() -> ProcessReading? {
        let now = monotonicSeconds()
        let pids = Self.allPIDs()
        var currentRates: [Int32: CounterRate] = [:]
        var usages: [ProcessUsage] = []

        for pid in pids where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }

            // pti_total_* are Mach absolute time units, which are not nanoseconds on Apple Silicon.
            let cpuTime = (info.pti_total_user + info.pti_total_system) * UInt64(timebase.numer) / UInt64(timebase.denom)
            var rate = cpuRates[pid] ?? CounterRate()
            let cpu = (rate.update(cpuTime, at: now) ?? 0) / 1_000_000_000
            currentRates[pid] = rate

            usages.append(ProcessUsage(pid: pid, name: Self.name(of: pid), cpu: cpu,
                                       memoryBytes: Self.footprint(of: pid) ?? info.pti_resident_size))
        }

        cpuRates = currentRates

        // Owner and start time are only needed for the listed rows, which can be stopped.
        func withIdentity(_ top: ArraySlice<ProcessUsage>) -> [ProcessUsage] {
            top.map { usage in
                var usage = usage
                if let identity = ProcessIdentity.read(pid: usage.pid) {
                    usage.ownerUID = identity.ownerUID
                    usage.startTime = identity.startTime
                }
                return usage
            }
        }

        return ProcessReading(
            topByCPU: withIdentity(usages.sorted { $0.cpu > $1.cpu }.prefix(limit)),
            topByMemory: withIdentity(usages.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit)),
            inspectedCount: usages.count,
            totalCount: pids.count
        )
    }

    private static func allPIDs() -> [Int32] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        // Leave headroom for processes started between the two calls.
        var pids = [Int32](repeating: 0, count: Int(estimate) + 32)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        return count > 0 ? Array(pids.prefix(Int(count))) : []
    }

    private static func name(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : "pid \(pid)"
    }

    /// Physical footprint is the "Memory" column in Activity Monitor; resident size overcounts shared pages.
    private static func footprint(of pid: Int32) -> UInt64? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? usage.ri_phys_footprint : nil
    }
}
