import NerdStatsCore
import SwiftUI

/// A titled card for one subsystem: a simple summary that everyone sees, plus optional
/// detail that only appears in Nerd mode.
struct SectionCard<Summary: View, Detail: View>: View {
    let title: String
    let systemImage: String
    var status: StatusLevel = .unknown
    @ViewBuilder let summary: () -> Summary
    @ViewBuilder let detail: () -> Detail

    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                if status != .unknown {
                    StatusBadge(level: status)
                }
            }
            summary()
            if settings.nerdMode {
                Divider()
                detail()
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

extension SectionCard where Detail == EmptyView {
    init(title: String, systemImage: String, status: StatusLevel = .unknown,
         @ViewBuilder summary: @escaping () -> Summary) {
        self.init(title: title, systemImage: systemImage, status: status, summary: summary, detail: { EmptyView() })
    }
}

struct StatusBadge: View {
    let level: StatusLevel

    var body: some View {
        Text(level.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(level.color.opacity(0.2)))
            .foregroundStyle(level.color)
    }
}

extension StatusLevel {
    var color: Color {
        switch self {
        case .normal: return .green
        case .busy: return .orange
        case .hot: return .red
        case .unknown: return .secondary
        }
    }
}

/// A label on the left and a value on the right.
struct StatRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
    }
}

/// A horizontal bar showing a 0...1 fraction.
struct UsageBar: View {
    let fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(tint)
                    .frame(width: geometry.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 6)
    }
}

/// A tiny line chart of recent values. Scales to `maxValue`, or to the largest value seen.
struct Sparkline: View {
    let values: [Double]
    var maxValue: Double?
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            let top = max(maxValue ?? values.max() ?? 1, .leastNonzeroMagnitude)
            let step = geometry.size.width / CGFloat(max(StatsCoordinator.historyLength - 1, 1))
            // Right-align so the newest sample is always at the right edge.
            let startX = geometry.size.width - CGFloat(max(values.count - 1, 0)) * step
            Path { path in
                for (index, value) in values.enumerated() {
                    let point = CGPoint(
                        x: startX + CGFloat(index) * step,
                        y: geometry.size.height * (1 - CGFloat(min(value / top, 1)))
                    )
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .frame(height: 28)
    }
}

/// A big number with a caption, used for the headline value of a section.
struct HeadlineValue: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Shown where a value cannot be read on this Mac.
struct UnavailableText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

/// Closure for opening the Settings window, injected by the app.
private struct OpenSettingsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openSettingsWindow: () -> Void {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
    }
}

/// Asks the user to confirm stopping a process; returns `true` to go ahead. Injected by the
/// app so the dialog can keep the dashboard popover open while it is shown.
private struct ConfirmProcessStopKey: EnvironmentKey {
    static let defaultValue: (ProcessUsage, ProcessStopAction) -> Bool = { _, _ in false }
}

extension EnvironmentValues {
    var confirmProcessStop: (ProcessUsage, ProcessStopAction) -> Bool {
        get { self[ConfirmProcessStopKey.self] }
        set { self[ConfirmProcessStopKey.self] = newValue }
    }
}
