/// Cumulative CPU time counters for one core (or the sum of all cores), in scheduler ticks.
///
/// The kernel only reports ever-increasing tick counts, so usage over an interval is
/// derived from the difference between two readings.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    public static let zero = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)

    public static func + (lhs: CPUTicks, rhs: CPUTicks) -> CPUTicks {
        CPUTicks(user: lhs.user &+ rhs.user, system: lhs.system &+ rhs.system,
                 idle: lhs.idle &+ rhs.idle, nice: lhs.nice &+ rhs.nice)
    }
}

/// CPU usage over an interval, each field in the range 0...1.
public struct CPUUsage: Equatable, Sendable {
    public var user: Double
    public var system: Double
    public var idle: Double

    public init(user: Double, system: Double, idle: Double) {
        self.user = user
        self.system = system
        self.idle = idle
    }

    /// Fraction of time spent doing work (user + system).
    public var total: Double { user + system }

    public static let idle = CPUUsage(user: 0, system: 0, idle: 1)

    /// Usage between two tick readings. `nice` time counts as user time, like Activity Monitor.
    ///
    /// Returns `nil` when no time has passed, or when a counter went backwards (for
    /// example after a core was taken offline), since no meaningful value exists then.
    public init?(from previous: CPUTicks, to current: CPUTicks) {
        guard current.user >= previous.user, current.system >= previous.system,
              current.idle >= previous.idle, current.nice >= previous.nice else { return nil }
        let user = Double(current.user - previous.user + current.nice - previous.nice)
        let system = Double(current.system - previous.system)
        let idle = Double(current.idle - previous.idle)
        let total = user + system + idle
        guard total > 0 else { return nil }
        self.init(user: user / total, system: system / total, idle: idle / total)
    }
}
