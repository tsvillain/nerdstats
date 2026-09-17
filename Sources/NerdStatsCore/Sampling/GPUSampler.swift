import Foundation
import IOKit

/// GPU utilization and memory from each IOAccelerator's "PerformanceStatistics".
///
/// Every Metal-capable GPU driver (Apple AGX, Intel, AMD) publishes this dictionary, but
/// the key names differ between vendors, so `GPUStatistics` checks the known variants.
public final class GPUSampler: Sampler {
    public init() {}

    public func sample() -> [GPUReading]? {
        var readings: [GPUReading] = []
        IORegistry.forEachService(matching: "IOAccelerator") { service in
            guard let stats = IORegistry.property("PerformanceStatistics", of: service) as? [String: Any] else { return }
            // The model name lives on the accelerator (Apple) or its parent PCI device (Intel/AMD).
            let name = IORegistry.string(from: IORegistry.property("model", of: service, searchParents: true))
                ?? "GPU \(readings.count + 1)"
            let totalMB = (IORegistry.property("VRAM,totalMB", of: service, searchParents: true) as? NSNumber)?.uint64Value
            readings.append(GPUReading(
                name: name,
                utilization: GPUStatistics.utilization(stats),
                memoryUsedBytes: GPUStatistics.memoryUsed(stats),
                memoryTotalBytes: totalMB.map { $0 * 1_048_576 }
            ))
        }
        return readings
    }
}

/// Interprets a PerformanceStatistics dictionary.
public enum GPUStatistics {
    public static func utilization(_ stats: [String: Any]) -> Double? {
        for key in ["Device Utilization %", "GPU Activity(%)", "Renderer Utilization %"] {
            if let value = stats.int64(key) {
                return min(1, max(0, Double(value) / 100))
            }
        }
        return nil
    }

    /// Dedicated VRAM in use on discrete GPUs, or system memory wired for the GPU on
    /// integrated and Apple Silicon GPUs.
    public static func memoryUsed(_ stats: [String: Any]) -> UInt64? {
        for key in ["vramUsedBytes", "In use system memory", "inUseVidMemoryBytes"] {
            if let value = stats.int64(key), value >= 0 {
                return UInt64(value)
            }
        }
        return nil
    }
}
