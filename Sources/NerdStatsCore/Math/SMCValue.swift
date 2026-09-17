import Foundation

/// Decodes raw SMC key bytes according to their four-character data type.
public enum SMCValue {
    /// Converts a four-character code such as "TC0P" to the big-endian integer the SMC expects.
    public static func fourCharCode(_ string: String) -> UInt32 {
        string.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    /// Converts an SMC integer code back to its four-character string.
    public static func string(fromFourCharCode code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Returns the numeric value of `bytes` for SMC data type `type`, or `nil` for
    /// unsupported types. Fixed-point types are big-endian; `flt ` (Apple Silicon) is a
    /// little-endian IEEE float.
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        func bigEndian(_ count: Int) -> UInt64? {
            guard bytes.count >= count else { return nil }
            return bytes.prefix(count).reduce(0) { ($0 << 8) | UInt64($1) }
        }
        switch type {
        case "ui8 ": return bigEndian(1).map { Double($0) }
        case "ui16": return bigEndian(2).map { Double($0) }
        case "ui32": return bigEndian(4).map { Double($0) }
        case "sp78": return bigEndian(2).map { Double(Int16(bitPattern: UInt16($0))) / 256 }
        case "fpe2": return bigEndian(2).map { Double($0) / 4 }
        case "fp88": return bigEndian(2).map { Double($0) / 256 }
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: raw))
        default: return nil
        }
    }
}
