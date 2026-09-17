import Foundation
import IOKit

/// Mounted volume capacities plus combined read/write throughput of all block devices.
public final class DiskSampler: Sampler {
    private var readRate = CounterRate()
    private var writeRate = CounterRate()

    public init() {}

    public func sample() -> DiskReading? {
        let now = monotonicSeconds()
        let (read, written) = Self.blockDeviceTotals()
        return DiskReading(
            volumes: Self.volumes(),
            readBytesPerSecond: readRate.update(read, at: now),
            writeBytesPerSecond: writeRate.update(written, at: now),
            totalReadBytes: read,
            totalWriteBytes: written
        )
    }

    private static let volumeKeys: [URLResourceKey] = [
        .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        .volumeAvailableCapacityKey, .volumeIsInternalKey, .volumeIsBrowsableKey,
    ]

    private static func volumes() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: volumeKeys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(volumeKeys)),
                  values.volumeIsBrowsable != false,
                  let total = values.volumeTotalCapacity, total > 0 else { return nil }
            // "Important usage" includes purgeable space, matching what Finder calls available.
            let available = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
                ?? UInt64(max(0, values.volumeAvailableCapacity ?? 0))
            return VolumeInfo(
                name: values.volumeName ?? url.lastPathComponent,
                mountPath: url.path,
                totalBytes: UInt64(total),
                availableBytes: min(available, UInt64(total)),
                isInternal: values.volumeIsInternal ?? false
            )
        }
    }

    /// Each physical disk has an IOBlockStorageDriver whose "Statistics" dictionary holds
    /// cumulative bytes read and written since it attached.
    private static func blockDeviceTotals() -> (read: UInt64, written: UInt64) {
        var read: UInt64 = 0
        var written: UInt64 = 0
        IORegistry.forEachService(matching: "IOBlockStorageDriver") { service in
            guard let stats = IORegistry.property("Statistics", of: service) as? [String: Any] else { return }
            read &+= UInt64(clamping: stats.int64("Bytes (Read)") ?? 0)
            written &+= UInt64(clamping: stats.int64("Bytes (Write)") ?? 0)
        }
        return (read, written)
    }
}
