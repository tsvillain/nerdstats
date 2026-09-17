import Foundation

/// Temperatures and fan speeds from the HID sensor hub (Apple Silicon) and the SMC (Intel,
/// plus fans on both). Anything that cannot be read is left out rather than guessed.
public final class SensorSampler: Sampler {
    private let hid = HIDTemperatureSensors()
    private let smc = SMCClient()
    /// SMC temperature keys that answered on the first sample; probing the full list every
    /// time would waste calls on keys this model does not have.
    private lazy var smcTemperatureKeys = SensorClassifier.intelSMCKeys.filter { smc?.read($0.key) != nil }

    /// The category `SensorReading.cpuCelsius` is derived from: CPU sensors where they
    /// exist, otherwise the SoC sensors it falls back to.
    private lazy var processorCategory: TemperatureSensor.Category = {
        let categories = (hid?.names ?? []).map(SensorClassifier.category(forHIDName:))
            + smcTemperatureKeys.map(\.category)
        return categories.contains(.cpu) ? .cpu : .soc
    }()

    public init() {}

    public func sample() -> SensorReading? {
        sample(processorOnly: false)
    }

    /// With `processorOnly`, reads just the sensors behind `SensorReading.cpuCelsius` and
    /// skips fans. Each sensor read is an IPC round trip, so this is much
    /// cheaper and is all the menu bar needs.
    public func sample(processorOnly: Bool) -> SensorReading? {
        let wanted: (TemperatureSensor.Category) -> Bool = { category in
            !processorOnly || category == self.processorCategory
        }

        let hidValues = hid?.read { wanted(SensorClassifier.category(forHIDName: $0)) } ?? []
        let hidNames = SensorClassifier.disambiguate(hidValues.map(\.name))
        var temperatures = zip(hidNames, hidValues).map { name, value in
            TemperatureSensor(name: name, category: SensorClassifier.category(forHIDName: value.name),
                              celsius: value.celsius, source: "HID")
        }
        let hidCategories = Set(temperatures.map(\.category))

        // Use SMC temperatures for anything HID did not cover (all of them on Intel).
        if let smc {
            for entry in smcTemperatureKeys where wanted(entry.category) && !hidCategories.contains(entry.category) {
                if let celsius = smc.read(entry.key), celsius > 0, celsius < 150 {
                    temperatures.append(TemperatureSensor(name: entry.name, category: entry.category,
                                                          celsius: celsius, source: "SMC \(entry.key)"))
                }
            }
        }

        temperatures.sort { ($0.category.rawValue, $0.name) < ($1.category.rawValue, $1.name) }
        return SensorReading(temperatures: temperatures, fans: processorOnly ? [] : readFans())
    }

    private func readFans() -> [FanReading] {
        guard let smc, let count = smc.read("FNum"), count > 0 else { return [] }
        return (0..<min(Int(count), 8)).compactMap { index in
            guard let rpm = smc.read("F\(index)Ac"), rpm >= 0 else { return nil }
            return FanReading(index: index, rpm: rpm, minRPM: smc.read("F\(index)Mn"), maxRPM: smc.read("F\(index)Mx"))
        }
    }
}
