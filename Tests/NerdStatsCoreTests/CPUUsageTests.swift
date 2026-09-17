@testable import NerdStatsCore
import XCTest

final class CPUUsageTests: XCTestCase {
    func testUsageIsComputedFromTickDeltas() throws {
        let previous = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let current = CPUTicks(user: 130, system: 60, idle: 910, nice: 0)

        let usage = try XCTUnwrap(CPUUsage(from: previous, to: current))

        // 100 ticks elapsed: 30 user, 10 system, 60 idle.
        XCTAssertEqual(usage.user, 0.3, accuracy: 1e-9)
        XCTAssertEqual(usage.system, 0.1, accuracy: 1e-9)
        XCTAssertEqual(usage.idle, 0.6, accuracy: 1e-9)
        XCTAssertEqual(usage.total, 0.4, accuracy: 1e-9)
    }

    func testNiceTimeCountsAsUser() throws {
        let previous = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let current = CPUTicks(user: 10, system: 0, idle: 80, nice: 10)

        let usage = try XCTUnwrap(CPUUsage(from: previous, to: current))

        XCTAssertEqual(usage.user, 0.2, accuracy: 1e-9)
    }

    func testNoElapsedTicksGivesNil() {
        let ticks = CPUTicks(user: 5, system: 5, idle: 5, nice: 5)
        XCTAssertNil(CPUUsage(from: ticks, to: ticks))
    }

    func testCounterGoingBackwardsGivesNil() {
        let previous = CPUTicks(user: 100, system: 100, idle: 100, nice: 0)
        let current = CPUTicks(user: 50, system: 120, idle: 150, nice: 0)
        XCTAssertNil(CPUUsage(from: previous, to: current))
    }

    func testTicksAddAcrossCores() {
        let sum = CPUTicks(user: 1, system: 2, idle: 3, nice: 4) + CPUTicks(user: 10, system: 20, idle: 30, nice: 40)
        XCTAssertEqual(sum, CPUTicks(user: 11, system: 22, idle: 33, nice: 44))
    }
}
