/// A fixed-size, oldest-first buffer of recent values used for sparklines.
public struct History: Equatable, Sendable {
    public let capacity: Int
    public private(set) var values: [Double] = []

    public init(capacity: Int = 60) {
        precondition(capacity > 0, "History capacity must be positive")
        self.capacity = capacity
    }

    public mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }

    public var latest: Double? { values.last }
    public var maximum: Double? { values.max() }
}
