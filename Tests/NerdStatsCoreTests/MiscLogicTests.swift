@testable import NerdStatsCore
import XCTest

final class HistoryTests: XCTestCase {
    func testKeepsOnlyTheNewestValues() {
        var history = History(capacity: 3)
        for value in 1...5 {
            history.append(Double(value))
        }
        XCTAssertEqual(history.values, [3, 4, 5])
        XCTAssertEqual(history.latest, 5)
        XCTAssertEqual(history.maximum, 5)
    }
}

final class StatusRulesTests: XCTestCase {
    func testThresholds() {
        XCTAssertEqual(StatusRules.load(0.2), .normal)
        XCTAssertEqual(StatusRules.load(0.9), .busy)
        XCTAssertEqual(StatusRules.load(nil), .unknown)
        XCTAssertEqual(StatusRules.temperature(55), .normal)
        XCTAssertEqual(StatusRules.temperature(88), .busy)
        XCTAssertEqual(StatusRules.temperature(99), .hot)
        XCTAssertEqual(StatusRules.memoryPressure(.critical), .hot)
    }

    func testWorstIgnoresUnknown() {
        XCTAssertEqual(StatusRules.worst([.normal, .unknown, .busy]), .busy)
        XCTAssertEqual(StatusRules.worst([.unknown, .unknown]), .unknown)
        XCTAssertEqual(StatusRules.worst([.hot, .normal]), .hot)
    }
}

final class GPUStatisticsTests: XCTestCase {
    func testAppleSiliconKeys() {
        let stats: [String: Any] = ["Device Utilization %": 37, "In use system memory": 605_569_024]
        XCTAssertEqual(GPUStatistics.utilization(stats), 0.37)
        XCTAssertEqual(GPUStatistics.memoryUsed(stats), 605_569_024)
    }

    func testDiscreteGPUKeys() {
        let stats: [String: Any] = ["GPU Activity(%)": 12, "vramUsedBytes": 1_000_000]
        XCTAssertEqual(GPUStatistics.utilization(stats), 0.12)
        XCTAssertEqual(GPUStatistics.memoryUsed(stats), 1_000_000)
    }

    func testMissingKeys() {
        XCTAssertNil(GPUStatistics.utilization([:]))
        XCTAssertNil(GPUStatistics.memoryUsed([:]))
    }
}

final class MemoryReadingTests: XCTestCase {
    func testUsedMatchesActivityMonitorDefinition() {
        let memory = MemoryReading(totalBytes: 1000, appBytes: 300, wiredBytes: 150, compressedBytes: 50,
                                   cachedBytes: 200, freeBytes: 300, swapUsedBytes: 0, swapTotalBytes: 0,
                                   pressure: .normal)
        XCTAssertEqual(memory.usedBytes, 500)
        XCTAssertEqual(memory.usedFraction, 0.5)
    }
}

final class NetworkInterfaceTests: XCTestCase {
    func testOnlyKnownHardwareInterfacesCount() {
        let known = ["en0", "en1", "bridge0"]
        XCTAssertTrue(NetworkInterfaces.isHardware("en0", knownNames: known))
        XCTAssertFalse(NetworkInterfaces.isHardware("utun4", knownNames: known))
        XCTAssertFalse(NetworkInterfaces.isHardware("bridge0", knownNames: known))
    }
}
