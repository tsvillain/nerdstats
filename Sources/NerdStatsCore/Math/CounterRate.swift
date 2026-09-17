import Foundation

/// Turns an ever-increasing byte counter into a per-second rate.
///
/// Feed it the raw counter on every sample. The first reading only establishes a
/// baseline. A counter that goes backwards (interface reset, disk ejected) or a baseline
/// older than `maxInterval` (the dashboard was closed for a while) yields `nil` and
/// starts over, rather than reporting a misleading spike or average.
public struct CounterRate: Sendable {
    public let maxInterval: TimeInterval
    private var last: (value: UInt64, time: TimeInterval)?

    public init(maxInterval: TimeInterval = 30) {
        self.maxInterval = maxInterval
    }

    /// Records `value` observed at `time` (seconds, monotonic) and returns bytes per second.
    @discardableResult
    public mutating func update(_ value: UInt64, at time: TimeInterval) -> Double? {
        defer { last = (value, time) }
        guard let last else { return nil }
        let elapsed = time - last.time
        guard elapsed > 0, elapsed <= maxInterval, value >= last.value else { return nil }
        return Double(value - last.value) / elapsed
    }
}

