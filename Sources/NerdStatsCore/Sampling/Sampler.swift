import Foundation

/// A source of readings for one subsystem (CPU, memory, sensors, …).
///
/// Samplers are classes because most keep state between calls: previous counters for
/// computing rates, or open connections to IOKit services. They are not thread-safe;
/// the app's coordinator only calls them from its own serial queue.
public protocol Sampler: AnyObject {
    associatedtype Reading
    /// Takes a new reading. May return `nil` when the hardware is absent (e.g. no battery).
    func sample() -> Reading?
}

/// Monotonic seconds, unaffected by wall-clock changes. Used to time counter deltas.
func monotonicSeconds() -> TimeInterval {
    ProcessInfo.processInfo.systemUptime
}
