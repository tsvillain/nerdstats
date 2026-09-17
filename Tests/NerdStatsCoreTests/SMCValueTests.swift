@testable import NerdStatsCore
import XCTest

final class SMCValueTests: XCTestCase {
    func testFourCharCodeRoundTrip() {
        let code = SMCValue.fourCharCode("TC0P")
        XCTAssertEqual(code, 0x5443_3050)
        XCTAssertEqual(SMCValue.string(fromFourCharCode: code), "TC0P")
    }

    func testSignedFixedPoint78() {
        XCTAssertEqual(SMCValue.decode(type: "sp78", bytes: [0x2A, 0x80]), 42.5)
        XCTAssertEqual(SMCValue.decode(type: "sp78", bytes: [0xFF, 0x00]), -1)
    }

    func testUnsignedFixedPointE2ForFanSpeeds() {
        // 1200 RPM * 4 = 4800 = 0x12C0
        XCTAssertEqual(SMCValue.decode(type: "fpe2", bytes: [0x12, 0xC0]), 1200)
    }

    func testLittleEndianFloat() throws {
        let bits = Float(1234.5).bitPattern
        let bytes = (0..<4).map { UInt8((bits >> ($0 * 8)) & 0xff) }
        XCTAssertEqual(try XCTUnwrap(SMCValue.decode(type: "flt ", bytes: bytes)), 1234.5, accuracy: 0.001)
    }

    func testIntegers() {
        XCTAssertEqual(SMCValue.decode(type: "ui8 ", bytes: [2]), 2)
        XCTAssertEqual(SMCValue.decode(type: "ui16", bytes: [0x01, 0x00]), 256)
        XCTAssertEqual(SMCValue.decode(type: "ui32", bytes: [0, 0, 1, 0]), 256)
    }

    func testUnsupportedOrShortInputGivesNil() {
        XCTAssertNil(SMCValue.decode(type: "ch8*", bytes: [1, 2, 3]))
        XCTAssertNil(SMCValue.decode(type: "sp78", bytes: [1]))
        XCTAssertNil(SMCValue.decode(type: "flt ", bytes: [0, 0]))
    }
}
