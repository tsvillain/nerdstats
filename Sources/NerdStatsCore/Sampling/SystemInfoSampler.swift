import Foundation
import IOKit

/// Static facts about the Mac. Everything except uptime is read once.
public final class SystemInfoSampler: Sampler {
    private lazy var info: SystemInfo = Self.readInfo()

    public init() {}

    public func sample() -> SystemInfo? { info }

    private static func readInfo() -> SystemInfo {
        let isAppleSilicon = Sysctl.int("hw.optional.arm64") == 1
        let modelIdentifier = Sysctl.string("hw.model") ?? "Mac"

        return SystemInfo(
            modelName: marketingName() ?? modelIdentifier,
            modelIdentifier: modelIdentifier,
            chipName: Sysctl.string("machdep.cpu.brand_string") ?? "Unknown CPU",
            architecture: isAppleSilicon ? .appleSilicon : .intel,
            physicalCores: Sysctl.int("hw.physicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount,
            logicalCores: Sysctl.int("hw.logicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount,
            coreClusters: coreClusters(),
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            osVersion: osVersion(),
            hostName: hostName(),
            bootTime: bootTime(),
            isTranslated: Sysctl.int("sysctl.proc_translated") == 1
        )
    }

    /// Apple Silicon Macs store a marketing name such as "MacBook Air (M1, 2020)" in the
    /// device tree. Intel Macs do not, so callers fall back to the model identifier.
    private static func marketingName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return IORegistry.string(from: IORegistry.property("product-name", of: entry))
    }

    /// Performance levels ("hw.perflevelN") describe P/E core clusters on Apple Silicon.
    private static func coreClusters() -> [SystemInfo.CoreCluster] {
        let levels = Sysctl.int("hw.nperflevels") ?? 0
        guard levels > 1 else { return [] }
        return (0..<levels).compactMap { level in
            guard let cores = Sysctl.int("hw.perflevel\(level).physicalcpu") else { return nil }
            let name = Sysctl.string("hw.perflevel\(level).name") ?? "Level \(level)"
            return SystemInfo.CoreCluster(name: name, physicalCores: cores)
        }
    }

    private static func osVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let build = Sysctl.string("kern.osversion").map { " (\($0))" } ?? ""
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)\(build)"
    }

    /// `ProcessInfo.hostName` can block on a DNS lookup, so read the kernel's name instead.
    private static func hostName() -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN))
        guard gethostname(&buffer, buffer.count) == 0 else { return "Unknown" }
        return String(cString: buffer)
    }

    private static func bootTime() -> Date? {
        guard let time = Sysctl.value("kern.boottime", as: timeval.self) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }
}
