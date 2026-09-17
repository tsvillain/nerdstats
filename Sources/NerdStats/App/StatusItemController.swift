import AppKit
import Combine
import NerdStatsCore
import SwiftUI

/// The values menu bar items show. Published only when a displayed value changes, so an
/// unchanged readout never redraws the menu bar.
@MainActor
final class MenuBarModel: ObservableObject {
    @Published private(set) var values = MenuBarValues()

    func update(with snapshot: SystemSnapshot, sampled: Set<Subsystem>) {
        let new = MenuBarValues(snapshot: snapshot, sampled: sampled)
        if new != values {
            values = new
        }
    }
}

/// Owns the menu bar items and the dashboard popover they open.
///
/// This uses AppKit `NSStatusItem`s rather than several SwiftUI `MenuBarExtra` scenes: a
/// status item button shows an SF Symbol and a text value side by side natively, which a
/// `MenuBarExtra` label does not reliably do, and every item can share one popover whose
/// content is rebuilt with the clicked metric first.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private enum Slot: Hashable {
        /// Plain app icon, shown only when no metric item is visible.
        case app
        case metric(MenuBarItem)

        var item: MenuBarItem? {
            if case let .metric(item) = self { return item }
            return nil
        }
    }

    private let coordinator: StatsCoordinator
    private let settings: AppSettings
    private let openSettings: () -> Void
    private let popover = NSPopover()
    private var slots: [Slot] = []
    private var statusItems: [Slot: NSStatusItem] = [:]
    private var rendered: [Slot: (symbol: String, text: String)] = [:]
    private var shownSlot: Slot?
    private var lastClose: (slot: Slot, time: TimeInterval)?
    private var cancellables: Set<AnyCancellable> = []

    init(coordinator: StatsCoordinator, settings: AppSettings, openSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.settings = settings
        self.openSettings = openSettings
        super.init()
        popover.behavior = .transient
        // Closing instantly keeps a click on another item from racing the close animation.
        popover.animates = false
        popover.delegate = self

        // Published values arrive before the properties change, so use the emitted values.
        Publishers.CombineLatest4(settings.$menuBarItems, settings.$cpuMenuBarReadout,
                                  settings.$temperatureUnit, coordinator.menuBar.$values)
            .sink { [weak self] items, cpuReadout, unit, values in
                self?.update(items: items, cpuReadout: cpuReadout, unit: unit, values: values)
            }
            .store(in: &cancellables)
    }

    private func update(items: Set<MenuBarItem>, cpuReadout: CPUMenuBarReadout,
                        unit: TemperatureUnit, values: MenuBarValues) {
        let visible = MenuBarLayout.visibleItems(enabled: items, hasBattery: values.hasBattery)
        let newSlots = visible.isEmpty ? [Slot.app] : visible.map(Slot.metric)
        if newSlots != slots {
            rebuild(newSlots)
        }
        for slot in slots {
            let symbol: String
            let text: String
            if let item = slot.item {
                symbol = MenuBarLayout.symbolName(for: item, values: values)
                text = MenuBarLayout.text(for: item, values: values, cpuReadout: cpuReadout, unit: unit)
            } else {
                symbol = MenuBarLayout.appSymbolName
                text = ""
            }
            guard rendered[slot].map({ $0 != (symbol, text) }) ?? true,
                  let button = statusItems[slot]?.button else { continue }
            rendered[slot] = (symbol, text)
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: slot.item?.title ?? "NerdStats")
            image?.isTemplate = true
            button.image = image
            button.title = text
            button.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
        }
    }

    private func rebuild(_ newSlots: [Slot]) {
        if let shownSlot, !newSlots.contains(shownSlot) {
            popover.performClose(nil)
        }
        for item in statusItems.values {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItems = [:]
        rendered = [:]
        // A new status item appears to the left of the app's existing ones, so create them
        // right to left to keep CPU, GPU, Memory, SSD, Battery reading left to right.
        for slot in newSlots.reversed() {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
                button.toolTip = slot.item.map { "NerdStats – \($0.title)" } ?? "NerdStats"
                button.target = self
                button.action = #selector(itemClicked(_:))
            }
            statusItems[slot] = item
        }
        slots = newSlots
    }

    @objc private func itemClicked(_ sender: NSStatusBarButton) {
        guard let slot = statusItems.first(where: { $0.value.button === sender })?.key else { return }
        if popover.isShown {
            let wasSameItem = shownSlot == slot
            popover.performClose(nil)
            if wasSameItem { return }
        }
        // A transient popover closes on mouse-down, before this action runs on mouse-up.
        // Without this check, clicking the open item to dismiss it would reopen it.
        if let lastClose, lastClose.slot == slot, ProcessInfo.processInfo.systemUptime - lastClose.time < 0.3 {
            return
        }
        show(slot, from: sender)
    }

    private func show(_ slot: Slot, from button: NSStatusBarButton) {
        // A fresh view per opening starts scrolled to the top, with the clicked metric first.
        let dashboard = DashboardView(focus: slot.item)
            .environmentObject(coordinator)
            .environmentObject(settings)
            .environment(\.openSettingsWindow) { [weak self] in
                self?.popover.performClose(nil)
                self?.openSettings()
            }
            .environment(\.confirmProcessStop) { [weak self] process, action in
                self?.confirmStop(process, action: action) ?? false
            }
        coordinator.dashboardDidAppear()
        let controller = NSHostingController(rootView: dashboard)
        popover.contentViewController = controller
        popover.contentSize = controller.view.fittingSize
        shownSlot = slot
        // An accessory app must be active for the transient popover to close on outside clicks.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
    }

    private func confirmStop(_ process: ProcessUsage, action: ProcessStopAction) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = action == .forceQuit ? .critical : .warning
        alert.messageText = "\(action.title) \(process.name) (PID \(process.pid))?"
        switch action {
        case .quit:
            alert.informativeText = "The process is asked to quit and may save its work first."
        case .forceQuit:
            alert.informativeText = "The process ends immediately. Any unsaved work in it will be lost."
        }
        alert.addButton(withTitle: action.title)
        alert.addButton(withTitle: "Cancel")
        // A transient popover closes when the alert takes focus, taking the result with it.
        popover.behavior = .applicationDefined
        defer { popover.behavior = .transient }
        return alert.runModal() == .alertFirstButtonReturn
    }

    func popoverWillClose(_ notification: Notification) {
        guard let shownSlot else { return }
        lastClose = (shownSlot, ProcessInfo.processInfo.systemUptime)
        statusItems[shownSlot]?.button?.highlight(false)
    }

    func popoverDidClose(_ notification: Notification) {
        shownSlot = nil
        popover.contentViewController = nil
        coordinator.dashboardDidDisappear()
    }
}
