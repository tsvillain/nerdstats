import Darwin

/// Typed wrappers around `sysctlbyname`, which reads kernel state by dotted name
/// (see `sysctl -a` for the full list).
public enum Sysctl {
    public static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    public static func int(_ name: String) -> Int? {
        value(name, as: Int64.self).map(Int.init)
            ?? value(name, as: Int32.self).map(Int.init)
    }

    /// Reads a fixed-size value (integer or C struct). Returns `nil` if the name is
    /// unknown or its size does not match `T`.
    public static func value<T>(_ name: String, as type: T.Type) -> T? {
        var size = MemoryLayout<T>.size
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard sysctlbyname(name, pointer, &size, nil, 0) == 0, size == MemoryLayout<T>.size else {
            return nil
        }
        return pointer.pointee
    }
}
