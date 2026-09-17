import Foundation
import NerdStatsCore

/// Prints a plain-text snapshot of every subsystem.
enum DumpCommand {
    static func run() {
        let sampler = SnapshotSampler()
        _ = sampler.sample(Set(Subsystem.allCases))
        // Rates and CPU usage need two readings to compare.
        Thread.sleep(forTimeInterval: 1)
        let snapshot = sampler.sample(Set(Subsystem.allCases))
        print(DumpFormatter.text(for: snapshot, unit: .celsius))
    }
}

enum DumpFormatter {
    static func text(for snapshot: SystemSnapshot, unit: TemperatureUnit) -> String {
        var lines: [String] = []
        func section(_ title: String) { lines.append("\n== \(title) ==") }
        func row(_ label: String, _ value: String) { lines.append("  \(label): \(value)") }

        if let system = snapshot.system {
            section("System")
            row("Model", "\(system.modelName) [\(system.modelIdentifier)]")
            row("Chip", system.chipName)
            row("Architecture", system.architecture.rawValue + (system.isTranslated ? " (Rosetta)" : ""))
            row("Cores", "\(system.physicalCores) physical, \(system.logicalCores) logical")
            for cluster in system.coreClusters {
                row("  \(cluster.name)", "\(cluster.physicalCores)")
            }
            row("Memory", Format.memory(system.memoryBytes))
            row("OS", system.osVersion)
            row("Host", system.hostName)
            row("Uptime", system.uptime.map { Format.duration(seconds: $0) } ?? "–")
        }

        if let cpu = snapshot.cpu {
            section("CPU")
            row("Total", "\(Format.percent(cpu.total.total)) (user \(Format.percent(cpu.total.user)), system \(Format.percent(cpu.total.system)))")
            row("Per core", cpu.perCore.map { Format.percent($0.total) }.joined(separator: " "))
            row("Load", cpu.loadAverages.map { String(format: "%.2f", $0) }.joined(separator: " "))
        }

        if let processes = snapshot.processes {
            section("Processes (\(processes.inspectedCount) of \(processes.totalCount) readable)")
            for process in processes.topByCPU {
                row("CPU", "\(process.name) \(Format.percent(process.cpu))")
            }
            for process in processes.topByMemory {
                row("Memory", "\(process.name) \(Format.memory(process.memoryBytes))")
            }
        }

        section("GPU")
        for gpu in snapshot.gpus ?? [] {
            row(gpu.name, "util \(Format.percent(gpu.utilization)), memory \(gpu.memoryUsedBytes.map { Format.memory($0) } ?? "–")")
        }

        if let memory = snapshot.memory {
            section("Memory")
            row("Used", "\(Format.memory(memory.usedBytes)) of \(Format.memory(memory.totalBytes))")
            row("App / Wired / Compressed", "\(Format.memory(memory.appBytes)) / \(Format.memory(memory.wiredBytes)) / \(Format.memory(memory.compressedBytes))")
            row("Cached", Format.memory(memory.cachedBytes))
            row("Swap", "\(Format.memory(memory.swapUsedBytes)) of \(Format.memory(memory.swapTotalBytes))")
            row("Pressure", memory.pressure.rawValue)
        }

        if let disk = snapshot.disk {
            section("Disk")
            for volume in disk.volumes {
                row(volume.name, "\(Format.bytes(volume.availableBytes)) free of \(Format.bytes(volume.totalBytes)) at \(volume.mountPath)")
            }
            row("Read / Write", "\(Format.rate(disk.readBytesPerSecond)) / \(Format.rate(disk.writeBytesPerSecond))")
        }

        if let network = snapshot.network {
            section("Network")
            row("Interface", "\(network.primaryInterface ?? "none") \(network.interfaceKind ?? "")")
            row("IPv4 / IPv6", "\(network.localIPv4 ?? "–") / \(network.localIPv6 ?? "–")")
            row("Down / Up", "\(Format.rate(network.downloadBytesPerSecond)) / \(Format.rate(network.uploadBytesPerSecond))")
            row("Totals", "\(Format.bytes(network.totalReceivedBytes)) received, \(Format.bytes(network.totalSentBytes)) sent")
        }

        section("Battery & Power")
        if let power = snapshot.power {
            row("Charge", "\(Format.percent(power.chargeFraction)) charging=\(power.isCharging) pluggedIn=\(power.isPluggedIn)")
            row("Cycles / Health", "\(power.cycleCount.map(String.init) ?? "–") / \(Format.percent(power.health))")
            row("Temperature", Format.temperature(power.temperatureCelsius, unit: unit))
            row("Adapter", "\(Format.watts(power.adapterWatts)) \(power.adapterName ?? "")")
            row("Battery / System", "\(Format.watts(power.batteryWatts)) / \(Format.watts(power.systemWatts))")
        } else {
            row("Battery", "not present")
        }

        section("Sensors")
        if let sensors = snapshot.sensors {
            row("CPU / GPU / Battery", "\(Format.temperature(sensors.cpuCelsius, unit: unit)) / \(Format.temperature(sensors.gpuCelsius, unit: unit)) / \(Format.temperature(sensors.batteryCelsius, unit: unit))")
            for sensor in sensors.temperatures {
                row("[\(sensor.category.rawValue)] \(sensor.name)", "\(Format.temperature(sensor.celsius, unit: unit)) (\(sensor.source))")
            }
            if sensors.fans.isEmpty { row("Fans", "none reported") }
            for fan in sensors.fans {
                row("Fan \(fan.index)", "\(Int(fan.rpm)) RPM")
            }
        }
        return lines.joined(separator: "\n")
    }
}
