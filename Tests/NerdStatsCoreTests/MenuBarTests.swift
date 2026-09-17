@testable import NerdStatsCore
import XCTest

final class MenuBarPreferencesTests: XCTestCase {
    func testFreshInstallShowsCPUUsageAndTemperature() {
        let result = MenuBarPreferences.resolve(storedItems: nil, storedCPUReadout: nil, legacyReadout: nil)
        XCTAssertEqual(result.items, [.cpu])
        XCTAssertEqual(result.cpuReadout, .usageAndTemperature)
    }

    func testMigratesLegacyReadout() {
        func migrate(_ legacy: String) -> (Set<MenuBarItem>, CPUMenuBarReadout) {
            let result = MenuBarPreferences.resolve(storedItems: nil, storedCPUReadout: nil, legacyReadout: legacy)
            return (result.items, result.cpuReadout)
        }
        XCTAssertEqual(migrate("icon").0, [])
        XCTAssertEqual(migrate("cpu").0, [.cpu])
        XCTAssertEqual(migrate("cpu").1, .usage)
        XCTAssertEqual(migrate("temperature").1, .temperature)
        XCTAssertEqual(migrate("cpuAndTemperature").1, .usageAndTemperature)
        XCTAssertEqual(migrate("memory").0, [.memory])
        XCTAssertEqual(migrate("unknown").0, [.cpu])
    }

    func testStoredValuesWinOverLegacy() {
        let result = MenuBarPreferences.resolve(storedItems: ["gpu", "battery", "bogus"], storedCPUReadout: "temperature",
                                                legacyReadout: "cpuAndTemperature")
        XCTAssertEqual(result.items, [.gpu, .battery])
        XCTAssertEqual(result.cpuReadout, .temperature)
    }

    func testEmptyStoredItemsStayEmpty() {
        let result = MenuBarPreferences.resolve(storedItems: [], storedCPUReadout: nil, legacyReadout: "cpu")
        XCTAssertEqual(result.items, [])
        XCTAssertEqual(result.cpuReadout, .usage)
    }
}

final class MenuBarLayoutTests: XCTestCase {
    func testVisibleItemsKeepOrderAndHideMissingBattery() {
        let all = Set(MenuBarItem.allCases)
        XCTAssertEqual(MenuBarLayout.visibleItems(enabled: all, hasBattery: nil), [.cpu, .gpu, .memory, .storage, .battery])
        XCTAssertEqual(MenuBarLayout.visibleItems(enabled: all, hasBattery: true), [.cpu, .gpu, .memory, .storage, .battery])
        XCTAssertEqual(MenuBarLayout.visibleItems(enabled: all, hasBattery: false), [.cpu, .gpu, .memory, .storage])
        XCTAssertEqual(MenuBarLayout.visibleItems(enabled: [.battery], hasBattery: false), [])
        XCTAssertEqual(MenuBarLayout.visibleItems(enabled: [.storage, .cpu], hasBattery: nil), [.cpu, .storage])
    }

    func testRequiredSubsystems() {
        XCTAssertEqual(MenuBarLayout.requiredSubsystems(enabled: [], cpuReadout: .usageAndTemperature), [.cpu])
        XCTAssertEqual(MenuBarLayout.requiredSubsystems(enabled: [.cpu], cpuReadout: .usage), [.cpu])
        XCTAssertEqual(MenuBarLayout.requiredSubsystems(enabled: [.cpu], cpuReadout: .temperature),
                       [.cpu, .processorTemperature])
        XCTAssertEqual(MenuBarLayout.requiredSubsystems(enabled: [.gpu, .memory, .storage, .battery], cpuReadout: .temperature),
                       [.cpu, .gpu, .memory, .disk, .power])
    }

    func testText() {
        var values = MenuBarValues()
        values.cpuPercent = 42
        values.cpuCelsius = 61
        values.gpuPercent = 7
        values.memoryUsedPercent = 63
        values.batteryPercent = 98
        XCTAssertEqual(MenuBarLayout.text(for: .cpu, values: values, cpuReadout: .usage, unit: .celsius), "42%")
        XCTAssertEqual(MenuBarLayout.text(for: .cpu, values: values, cpuReadout: .temperature, unit: .fahrenheit), "142°F")
        XCTAssertEqual(MenuBarLayout.text(for: .cpu, values: values, cpuReadout: .usageAndTemperature, unit: .celsius), "42% 61°C")
        XCTAssertEqual(MenuBarLayout.text(for: .gpu, values: values, cpuReadout: .usage, unit: .celsius), "7%")
        XCTAssertEqual(MenuBarLayout.text(for: .memory, values: values, cpuReadout: .usage, unit: .celsius), "63%")
        XCTAssertEqual(MenuBarLayout.text(for: .storage, values: values, cpuReadout: .usage, unit: .celsius), "–")
        XCTAssertEqual(MenuBarLayout.text(for: .battery, values: values, cpuReadout: .usage, unit: .celsius), "98%")
    }

    func testSymbolsAreDistinct() {
        let values = MenuBarValues()
        let symbols = Set(MenuBarItem.allCases.map { MenuBarLayout.symbolName(for: $0, values: values) } + [MenuBarLayout.appSymbolName])
        XCTAssertEqual(symbols.count, MenuBarItem.allCases.count + 1)

        var battery = MenuBarValues()
        battery.batteryPercent = 30
        XCTAssertEqual(MenuBarLayout.symbolName(for: .battery, values: battery), "battery.25")
        battery.isCharging = true
        XCTAssertEqual(MenuBarLayout.symbolName(for: .battery, values: battery), "battery.100.bolt")
    }

    func testDashboardPutsFocusFirst() {
        XCTAssertEqual(DashboardSection.ordered(focus: nil), DashboardSection.allCases)
        let ordered = DashboardSection.ordered(focus: .battery)
        XCTAssertEqual(ordered.first, .battery)
        XCTAssertEqual(ordered.count, DashboardSection.allCases.count)
        XCTAssertEqual(DashboardSection.ordered(focus: .storage).prefix(3), [.storage, .system, .processor])
    }
}

final class MenuBarValuesTests: XCTestCase {
    private func volume(_ path: String, total: UInt64, available: UInt64, isInternal: Bool = true) -> VolumeInfo {
        VolumeInfo(name: path, mountPath: path, totalBytes: total, availableBytes: available, isInternal: isInternal)
    }

    func testReadsOnlySampledSubsystems() {
        var snapshot = SystemSnapshot()
        snapshot.cpu = CPUReading(total: CPUUsage(user: 0.3, system: 0.12, idle: 0.58), perCore: [], loadAverages: [])
        snapshot.gpus = [GPUReading(index: 0, name: "A", utilization: 0.2),
                         GPUReading(index: 1, name: "B", utilization: 0.55)]
        snapshot.memory = MemoryReading(totalBytes: 1000, appBytes: 300, wiredBytes: 150, compressedBytes: 50,
                                        cachedBytes: 200, freeBytes: 300, swapUsedBytes: 0, swapTotalBytes: 0,
                                        pressure: .normal)
        snapshot.disk = DiskReading(volumes: [volume("/Volumes/USB", total: 100, available: 90, isInternal: false),
                                              volume("/", total: 200, available: 50)],
                                    readBytesPerSecond: nil, writeBytesPerSecond: nil, totalReadBytes: 0, totalWriteBytes: 0)

        let cpuOnly = MenuBarValues(snapshot: snapshot, sampled: [.cpu])
        XCTAssertEqual(cpuOnly.cpuPercent, 42)
        XCTAssertNil(cpuOnly.gpuPercent)
        XCTAssertNil(cpuOnly.memoryUsedPercent)
        XCTAssertNil(cpuOnly.storageUsedPercent)
        XCTAssertNil(cpuOnly.hasBattery)

        let all = MenuBarValues(snapshot: snapshot, sampled: Set(Subsystem.allCases))
        XCTAssertEqual(all.gpuPercent, 55)
        XCTAssertEqual(all.memoryUsedPercent, 50)
        XCTAssertEqual(all.storageUsedPercent, 75)
        XCTAssertEqual(all.hasBattery, false)
        XCTAssertNil(all.batteryPercent)
    }

    func testStartupVolumeFallsBackToInternal() {
        let volumes = [volume("/Volumes/USB", total: 1, available: 1, isInternal: false), volume("/Volumes/Data", total: 1, available: 1)]
        XCTAssertEqual(MenuBarValues.startupVolume(volumes)?.mountPath, "/Volumes/Data")
        XCTAssertNil(MenuBarValues.startupVolume([]))
    }
}
