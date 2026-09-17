/// A plain-language verdict shown to non-technical users. Ordered from best to worst.
public enum StatusLevel: Comparable, Sendable, CaseIterable {
    case normal, busy, hot, unknown

    public static func < (lhs: StatusLevel, rhs: StatusLevel) -> Bool {
        // `unknown` never outranks a real reading.
        lhs.severity < rhs.severity
    }

    private var severity: Int {
        switch self {
        case .unknown: return -1
        case .normal: return 0
        case .busy: return 1
        case .hot: return 2
        }
    }

    public var title: String {
        switch self {
        case .normal: return "Normal"
        case .busy: return "Busy"
        case .hot: return "Hot"
        case .unknown: return "Unknown"
        }
    }
}

/// Thresholds that translate raw numbers into a `StatusLevel`.
public enum StatusRules {
    /// CPU or GPU load (0...1).
    public static func load(_ fraction: Double?) -> StatusLevel {
        guard let fraction else { return .unknown }
        return fraction < 0.6 ? .normal : .busy
    }

    /// Chip temperature in °C. Apple Silicon and Intel CPUs throttle around 95–105 °C.
    public static func temperature(_ celsius: Double?) -> StatusLevel {
        guard let celsius else { return .unknown }
        switch celsius {
        case ..<80: return .normal
        case ..<95: return .busy
        default: return .hot
        }
    }

    public static func memoryPressure(_ pressure: MemoryPressure) -> StatusLevel {
        switch pressure {
        case .normal: return .normal
        case .warning: return .busy
        case .critical: return .hot
        case .unknown: return .unknown
        }
    }

    /// Fraction of a disk that is used (0...1).
    public static func diskUsage(_ fraction: Double) -> StatusLevel {
        fraction < 0.9 ? .normal : .busy
    }

    /// The worst of several statuses, ignoring unknowns.
    public static func worst(_ levels: [StatusLevel]) -> StatusLevel {
        levels.filter { $0 != .unknown }.max() ?? .unknown
    }
}
