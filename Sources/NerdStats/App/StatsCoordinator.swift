import Combine
import Foundation
import NerdStatsCore

/// Metrics that keep a short history for sparklines.
enum Metric: CaseIterable {
    case cpu, gpu, memory, diskRead, diskWrite, download, upload, cpuTemperature, systemPower
}

/// The single place that decides when and what to sample.
///
/// A timer fires every `refreshInterval` seconds. While the dashboard is closed only the
/// subsystems the menu bar readout needs are sampled, which keeps NerdStats' own CPU cost
/// negligible. Opening the dashboard samples immediately and then refreshes everything.
/// Samplers run on a private serial queue; results are published on the main thread.
///
/// Publishing makes SwiftUI re-evaluate every observing view, which costs far more than the
/// sampling itself. So while the dashboard is closed only `menuBar` is updated, and only
/// when a value it displays actually changes.
@MainActor
final class StatsCoordinator: ObservableObject {
    static let historyLength = 60

    /// Dashboard data, published only while the dashboard is open.
    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var history: [Metric: History] = [:]
    @Published private(set) var publicIP: PublicIPState = .notRequested

    let menuBar = MenuBarModel()

    enum PublicIPState: Equatable {
        case notRequested, loading, loaded(String), failed
    }

    let settings: AppSettings
    private let sampler = SnapshotSampler()
    private let queue = DispatchQueue(label: "NerdStats.sampling", qos: .utility)
    private var timer: Timer?
    private var isSampling = false
    private var needsAnotherSample = false
    private var cancellables: Set<AnyCancellable> = []

    private var isDashboardVisible = false
    private var latestSnapshot = SystemSnapshot()
    private var latestHistory: [Metric: History] = [:]

    init(settings: AppSettings) {
        self.settings = settings
        // Restart the timer when the interval changes, and resample when the readout needs new data.
        settings.$refreshInterval.dropFirst().removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.restartTimer() } }
            .store(in: &cancellables)
        settings.$menuBarReadout.dropFirst().removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.sampleNow() } }
            .store(in: &cancellables)
    }

    func start() {
        sampleNow()
        restartTimer()
    }

    func dashboardDidAppear() {
        guard !isDashboardVisible else { return }
        isDashboardVisible = true
        // Show what is already known straight away, then fetch everything else.
        snapshot = latestSnapshot
        history = latestHistory
        sampleNow()
    }

    func dashboardDidDisappear() {
        isDashboardVisible = false
    }

    func fetchPublicIP() {
        publicIP = .loading
        Task {
            do {
                publicIP = .loaded(try await PublicIPLookup.fetch())
            } catch {
                publicIP = .failed
            }
        }
    }

    private var subsystemsToSample: Set<Subsystem> {
        if isDashboardVisible { return Set(Subsystem.allCases) }
        return settings.menuBarReadout.requiredSubsystems
    }

    private func restartTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleNow() }
        }
        // Let the system coalesce wake-ups to save energy.
        timer.tolerance = settings.refreshInterval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sampleNow() {
        // Never run two samples at once. If one is in flight, run again once it finishes so a
        // request such as opening the dashboard is not lost.
        guard !isSampling else {
            needsAnotherSample = true
            return
        }
        isSampling = true
        needsAnotherSample = false
        let subsystems = subsystemsToSample
        let sampler = self.sampler
        queue.async {
            let snapshot = sampler.sample(subsystems)
            DispatchQueue.main.async {
                self.isSampling = false
                self.publish(snapshot, sampled: subsystems)
                if self.needsAnotherSample {
                    self.sampleNow()
                }
            }
        }
    }

    private func publish(_ snapshot: SystemSnapshot, sampled subsystems: Set<Subsystem>) {
        latestSnapshot = snapshot
        if subsystems.contains(.cpu) { record(.cpu, snapshot.cpu?.total.total) }
        if subsystems.contains(.gpu) { record(.gpu, snapshot.gpus?.compactMap(\.utilization).max()) }
        if subsystems.contains(.memory) { record(.memory, snapshot.memory?.usedFraction) }
        if subsystems.contains(.disk) {
            record(.diskRead, snapshot.disk?.readBytesPerSecond)
            record(.diskWrite, snapshot.disk?.writeBytesPerSecond)
        }
        if subsystems.contains(.network) {
            record(.download, snapshot.network?.downloadBytesPerSecond)
            record(.upload, snapshot.network?.uploadBytesPerSecond)
        }
        if !subsystems.isDisjoint(with: [.sensors, .processorTemperature]) {
            record(.cpuTemperature, snapshot.sensors?.cpuCelsius)
        }
        if subsystems.contains(.power) { record(.systemPower, snapshot.power?.systemWatts) }

        menuBar.update(with: snapshot)
        if isDashboardVisible {
            self.snapshot = snapshot
            history = latestHistory
        }
    }

    private func record(_ metric: Metric, _ value: Double?) {
        guard let value, value.isFinite else { return }
        latestHistory[metric, default: History(capacity: Self.historyLength)].append(value)
    }
}
