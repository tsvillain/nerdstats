@testable import NerdStatsCore
import XCTest

final class CounterRateTests: XCTestCase {
    func testFirstReadingOnlySetsBaseline() {
        var rate = CounterRate()
        XCTAssertNil(rate.update(1_000, at: 10))
    }

    func testRateIsBytesPerSecond() {
        var rate = CounterRate()
        rate.update(1_000, at: 10)
        XCTAssertEqual(rate.update(5_000, at: 12), 2_000)
        XCTAssertEqual(rate.update(5_000, at: 13), 0)
    }

    func testCounterResetGivesNilThenRecovers() {
        var rate = CounterRate()
        rate.update(10_000, at: 0)
        XCTAssertNil(rate.update(100, at: 1), "a counter that went backwards is a reset, not negative traffic")
        XCTAssertEqual(rate.update(600, at: 2), 500)
    }

    func testStaleBaselineGivesNil() {
        var rate = CounterRate(maxInterval: 30)
        rate.update(0, at: 0)
        XCTAssertNil(rate.update(1_000_000, at: 120), "a long gap would report a misleading average")
        XCTAssertEqual(rate.update(1_000_100, at: 121), 100)
    }

    func testNonIncreasingTimeGivesNil() {
        var rate = CounterRate()
        rate.update(0, at: 5)
        XCTAssertNil(rate.update(100, at: 5))
    }
}
