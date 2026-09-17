@testable import NerdStatsCore
import XCTest

final class SensorTests: XCTestCase {
    func testClassifiesAppleSiliconHIDNames() {
        XCTAssertEqual(SensorClassifier.category(forHIDName: "pACC MTR Temp Sensor2"), .cpu)
        XCTAssertEqual(SensorClassifier.category(forHIDName: "eACC MTR Temp Sensor0"), .cpu)
        XCTAssertEqual(SensorClassifier.category(forHIDName: "GPU MTR Temp Sensor1"), .gpu)
        XCTAssertEqual(SensorClassifier.category(forHIDName: "gas gauge battery"), .battery)
        XCTAssertEqual(SensorClassifier.category(forHIDName: "NAND CH0 temp"), .storage)
        XCTAssertEqual(SensorClassifier.category(forHIDName: "PMU tdie1"), .soc)
        XCTAssertEqual(SensorClassifier.category(forHIDName: "SOC MTR Temp Sensor0"), .soc)
        XCTAssertEqual(SensorClassifier.category(forHIDName: "ANE MTR Temp Sensor1"), .other)
        XCTAssertEqual(SensorClassifier.category(forHIDName: "PMU2 tcal"), .other)
    }

    func testDuplicateNamesAreNumbered() {
        XCTAssertEqual(
            SensorClassifier.disambiguate(["battery", "cpu", "battery", "battery"]),
            ["battery", "cpu", "battery 2", "battery 3"]
        )
    }

    func testSummaryTemperatures() {
        let reading = SensorReading(temperatures: [
            sensor("p1", .cpu, 60), sensor("p2", .cpu, 72),
            sensor("g", .gpu, 40),
            sensor("b1", .battery, 30), sensor("b2", .battery, 34),
        ], fans: [])

        XCTAssertEqual(reading.cpuCelsius, 72)
        XCTAssertEqual(reading.gpuCelsius, 40)
        XCTAssertEqual(reading.batteryCelsius, 32)
    }

    func testProcessorFallsBackToHottestSoCSensor() {
        let reading = SensorReading(temperatures: [sensor("tdev", .soc, 44), sensor("tdie", .soc, 95)], fans: [])
        XCTAssertEqual(reading.cpuCelsius, 95)
        XCTAssertNil(SensorReading.empty.cpuCelsius)
    }

    private func sensor(_ name: String, _ category: TemperatureSensor.Category, _ celsius: Double) -> TemperatureSensor {
        TemperatureSensor(name: name, category: category, celsius: celsius, source: "test")
    }
}
