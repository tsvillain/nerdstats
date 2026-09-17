@testable import NerdStatsCore
import XCTest

final class BatteryTests: XCTestCase {
    func testHealthIsMaxOverDesignCapacity() throws {
        let health = try XCTUnwrap(BatteryMath.health(maxCapacity: 3796, designCapacity: 4382))
        XCTAssertEqual(health, 0.8663, accuracy: 0.0001)
        XCTAssertNil(BatteryMath.health(maxCapacity: 3000, designCapacity: 0))
        XCTAssertNil(BatteryMath.health(maxCapacity: nil, designCapacity: 4000))
    }

    func testChargeFractionWorksForPercentAndMilliampHours() {
        XCTAssertEqual(BatteryMath.chargeFraction(current: 57, max: 100), 0.57)       // Apple Silicon
        XCTAssertEqual(BatteryMath.chargeFraction(current: 2500, max: 5000), 0.5)     // Intel (mAh)
        XCTAssertEqual(BatteryMath.chargeFraction(current: 5100, max: 5000), 1)       // clamped
        XCTAssertNil(BatteryMath.chargeFraction(current: 10, max: 0))
    }

    func testMinutesRemainingSentinels() {
        XCTAssertNil(BatteryMath.minutesRemaining(65535), "65535 means still calculating")
        XCTAssertNil(BatteryMath.minutesRemaining(0))
        XCTAssertEqual(BatteryMath.minutesRemaining(185), 185)
    }

    func testSignedRegistryIntegers() {
        // -1500 mA stored as an unsigned 64-bit value.
        let raw = Int64(bitPattern: 18_446_744_073_709_550_116)
        XCTAssertEqual(BatteryMath.signed(raw), -1500)
        XCTAssertEqual(BatteryMath.signed(1200), 1200)
        XCTAssertEqual(BatteryMath.signed(Int64(UInt32.max - 99)), -100)
    }

    func testParsesAppleSiliconProperties() throws {
        let properties: [String: Any] = [
            "CurrentCapacity": 100, "MaxCapacity": 100, "DesignCapacity": 4382,
            "AppleRawMaxCapacity": 3666, "NominalChargeCapacity": 3796,
            "CycleCount": 458, "ExternalConnected": true, "IsCharging": false, "FullyCharged": true,
            "TimeRemaining": 65535, "Voltage": 12757, "InstantAmperage": 0,
            "PowerTelemetryData": ["SystemPowerIn": 3767],
        ]
        let reading = try XCTUnwrap(BatteryParser.parse(properties, adapter: ["Watts": 90, "Name": "USB-C"]))

        XCTAssertEqual(reading.chargeFraction, 1)
        XCTAssertEqual(try XCTUnwrap(reading.health), 3796.0 / 4382.0, accuracy: 1e-9)
        XCTAssertEqual(reading.cycleCount, 458)
        XCTAssertTrue(reading.isPluggedIn)
        XCTAssertNil(reading.minutesToEmpty)
        XCTAssertEqual(reading.adapterWatts, 90)
        XCTAssertEqual(reading.adapterName, "USB-C")
        XCTAssertEqual(try XCTUnwrap(reading.systemWatts), 3.767, accuracy: 1e-9)
        XCTAssertNil(reading.temperatureCelsius)
    }

    func testParsesIntelPropertiesOnBattery() throws {
        let properties: [String: Any] = [
            "CurrentCapacity": 3000, "MaxCapacity": 6000, "DesignCapacity": 6600,
            "CycleCount": 120, "ExternalConnected": false, "IsCharging": false,
            "TimeRemaining": 240, "Voltage": 12000,
            "InstantAmperage": NSNumber(value: UInt64(18_446_744_073_709_550_616)), // -1000 mA
            "Temperature": 3050,
        ]
        let reading = try XCTUnwrap(BatteryParser.parse(properties, adapter: nil))

        XCTAssertEqual(reading.chargeFraction, 0.5)
        XCTAssertEqual(try XCTUnwrap(reading.health), 6000.0 / 6600.0, accuracy: 1e-9)
        XCTAssertEqual(reading.minutesToEmpty, 240)
        XCTAssertEqual(reading.temperatureCelsius, 30.5)
        XCTAssertEqual(try XCTUnwrap(reading.batteryWatts), -12, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(reading.systemWatts), 12, accuracy: 1e-9)
        XCTAssertNil(reading.adapterWatts)
    }

    func testNoBatteryInstalled() {
        XCTAssertNil(BatteryParser.parse(["BatteryInstalled": false], adapter: nil))
    }
}
