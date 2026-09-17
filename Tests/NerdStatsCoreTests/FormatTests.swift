@testable import NerdStatsCore
import XCTest

final class FormatTests: XCTestCase {
    func testBytesUseDecimalUnits() {
        XCTAssertEqual(Format.bytes(UInt64(0)), "0 B")
        XCTAssertEqual(Format.bytes(UInt64(999)), "999 B")
        XCTAssertEqual(Format.bytes(UInt64(1_500)), "1.5 KB")
        XCTAssertEqual(Format.bytes(UInt64(245_000_000_000)), "245 GB")
        XCTAssertEqual(Format.bytes(-5.0), "0 B")
        XCTAssertEqual(Format.bytes(Double.nan), "–")
    }

    func testMemoryUsesBinaryUnits() {
        XCTAssertEqual(Format.memory(8 * 1_073_741_824), "8.0 GB")
        XCTAssertEqual(Format.memory(512 * 1_048_576), "512 MB")
    }

    func testRate() {
        XCTAssertEqual(Format.rate(12_000_000), "12 MB/s")
        XCTAssertEqual(Format.rate(nil), "–")
    }

    func testPercent() {
        XCTAssertEqual(Format.percent(0.424), "42%")
        XCTAssertEqual(Format.percent(1), "100%")
        XCTAssertEqual(Format.percent(nil), "–")
    }

    func testTemperatureConversion() {
        XCTAssertEqual(Format.temperature(54.4, unit: .celsius), "54°C")
        XCTAssertEqual(Format.temperature(100, unit: .fahrenheit), "212°F")
        XCTAssertEqual(Format.convert(celsius: -40, to: .fahrenheit), -40)
        XCTAssertEqual(Format.temperature(nil, unit: .celsius), "–")
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(seconds: 59), "0m")
        XCTAssertEqual(Format.duration(seconds: 12 * 60), "12m")
        XCTAssertEqual(Format.duration(seconds: 2 * 3600 + 5 * 60), "2h 05m")
        XCTAssertEqual(Format.duration(seconds: 3 * 86400 + 4 * 3600 + 59), "3d 4h")
    }

    func testWatts() {
        XCTAssertEqual(Format.watts(5.24), "5.2 W")
        XCTAssertEqual(Format.watts(90), "90 W")
        XCTAssertEqual(Format.watts(nil), "–")
    }
}
