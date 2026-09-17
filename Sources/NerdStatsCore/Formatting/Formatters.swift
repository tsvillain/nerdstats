import Foundation

/// Temperature display unit chosen in Settings.
public enum TemperatureUnit: String, CaseIterable, Sendable, Identifiable {
    case celsius, fahrenheit
    public var id: String { rawValue }
    public var symbol: String { self == .celsius ? "°C" : "°F" }
}

/// Human-readable formatting shared by the menu bar, dashboard and `--dump` output.
public enum Format {
    private static let byteUnits = ["B", "KB", "MB", "GB", "TB", "PB"]

    /// Decimal (base-1000) sizes for storage and network, matching Finder, e.g. "1.5 GB".
    public static func bytes(_ value: Double) -> String {
        scaled(value, base: 1000)
    }

    public static func bytes(_ value: UInt64) -> String { bytes(Double(value)) }

    /// Binary (base-1024) sizes for RAM, matching Activity Monitor and "About This Mac",
    /// so an 8 GiB Mac shows "8.0 GB" rather than "8.6 GB".
    public static func memory(_ value: UInt64) -> String {
        scaled(Double(value), base: 1024)
    }

    private static func scaled(_ value: Double, base: Double) -> String {
        guard value.isFinite else { return "–" }
        var scaled = max(0, value)
        var unit = 0
        while scaled >= base, unit < byteUnits.count - 1 {
            scaled /= base
            unit += 1
        }
        if unit == 0 { return "\(Int(scaled)) B" }
        let decimals = scaled < 10 ? 1 : 0
        return String(format: "%.\(decimals)f %@", scaled, byteUnits[unit])
    }

    /// A transfer rate such as "12 MB/s". `nil` renders as a dash.
    public static func rate(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else { return "–" }
        return bytes(bytesPerSecond) + "/s"
    }

    /// A 0...1 fraction as a whole percentage, e.g. "42%".
    public static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return "–" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    public static func convert(celsius: Double, to unit: TemperatureUnit) -> Double {
        unit == .celsius ? celsius : celsius * 9 / 5 + 32
    }

    /// A temperature such as "54°C". Input is always Celsius.
    public static func temperature(_ celsius: Double?, unit: TemperatureUnit) -> String {
        guard let celsius, celsius.isFinite else { return "–" }
        return "\(Int(convert(celsius: celsius, to: unit).rounded()))\(unit.symbol)"
    }

    /// A duration such as "3d 4h", "2h 05m" or "12m".
    public static func duration(seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        return "\(minutes)m"
    }

    public static func watts(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "–" }
        return String(format: value < 10 ? "%.1f W" : "%.0f W", value)
    }
}
