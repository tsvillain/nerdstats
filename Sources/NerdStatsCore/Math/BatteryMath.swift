/// Pure helpers for interpreting AppleSmartBattery registry values.
public enum BatteryMath {
    /// Battery health as a fraction of the original design capacity (can exceed 1 when new).
    public static func health(maxCapacity: Int?, designCapacity: Int?) -> Double? {
        guard let maxCapacity, let designCapacity, maxCapacity > 0, designCapacity > 0 else { return nil }
        return Double(maxCapacity) / Double(designCapacity)
    }

    /// Charge level as a fraction.
    ///
    /// Apple Silicon reports `CurrentCapacity`/`MaxCapacity` as percentages (x/100), Intel
    /// Macs report them in mAh; the ratio is correct in both cases.
    public static func chargeFraction(current: Int?, max: Int?) -> Double? {
        guard let current, let max, max > 0 else { return nil }
        return min(1, Swift.max(0, Double(current) / Double(max)))
    }

    /// The registry uses 65535 to mean "still calculating"; 0 means "not applicable".
    public static func minutesRemaining(_ raw: Int?) -> Int? {
        guard let raw, raw > 0, raw < 65535 else { return nil }
        return raw
    }

    /// Signed registry integers (e.g. `InstantAmperage`) are stored as 64-bit unsigned
    /// numbers, so a small negative value shows up as a huge positive one.
    public static func signed(_ raw: Int64) -> Int64 {
        if raw > Int64(Int32.max) || raw < Int64(Int32.min) {
            return Int64(Int32(truncatingIfNeeded: raw))
        }
        return raw
    }

    /// Power in watts from millivolts and milliamps (sign indicates direction).
    public static func watts(millivolts: Int64, milliamps: Int64) -> Double {
        Double(millivolts) * Double(milliamps) / 1_000_000
    }
}
