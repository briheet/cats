import SwiftUI

struct BrandMark: View {
    @Environment(\.catsPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    var size: CGFloat = 29
    var body: some View {
        Text("C").font(.system(size: size * 0.72, weight: .semibold))
            .foregroundStyle(
                palette.color(
                    "text",
                    fallback: scheme == .dark ? Color(red: 0.86, green: 0.91, blue: 1) : palette.ink
                )
            )
            .frame(width: size, height: size)
            .background(
                palette.surface(scheme).opacity(scheme == .dark ? 0.85 : 0.45),
                in: RoundedRectangle(cornerRadius: size * 0.22)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.22).strokeBorder(
                    .white.opacity(0.06), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }
}

struct Brand: View {
    @Environment(\.catsPalette) private var palette
    var subtitle: String? = nil
    var body: some View {
        HStack(spacing: 9) {
            BrandMark()
            VStack(alignment: .leading, spacing: 2) {
                Text("Cats").font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(palette.muted).lineLimit(
                        1)
                }
            }
        }
    }
}

struct Spend: View {
    @Environment(\.catsPalette) private var palette
    let value: Double
    var size: CGFloat = 32
    var body: some View {
        Text(Display.money(value)).font(.system(size: size, weight: .medium))
            .monospacedDigit().minimumScaleFactor(0.55).lineLimit(1)
    }
}

struct BudgetBar: View {
    @Environment(\.catsPalette) private var palette
    let today: TelemetryState.Today
    var body: some View {
        ProgressView(value: min(max(today.budgetFraction, 0), 1))
            .progressViewStyle(ThinProgressStyle(height: 7))
            .tint(
                today.budgetState == "exceeded"
                    ? palette.error
                    : today.budgetState == "warning" ? palette.warning : palette.mint
            )
            .accessibilityLabel("Daily budget").accessibilityValue(
                today.budgetFraction.formatted(.percent))
    }
}

struct ThinProgressStyle: ProgressViewStyle {
    @Environment(\.catsPalette) private var palette
    var height: CGFloat = 6
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            Capsule().fill(palette.slate.opacity(0.18))
                .overlay(alignment: .leading) {
                    Capsule().fill(.tint).opacity(0.90)
                        .frame(
                            width: geometry.size.width
                                * min(max(configuration.fractionCompleted ?? 0, 0), 1))
                }
        }.frame(height: height)
    }
}

struct ProviderIcon: View {
    @Environment(\.catsPalette) private var palette
    let name: String
    var body: some View {
        Image(
            systemName: name == "Claude"
                ? "asterisk" : name == "Codex" ? "point.3.connected.trianglepath.dotted" : "cpu"
        )
        .font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
        .frame(width: 28, height: 28)
        .background(palette.provider(name).opacity(0.90), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.24), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }
}

struct ProviderRow: View {
    @Environment(\.catsPalette) private var palette
    let provider: ProviderUsage
    var showBar = true
    var body: some View {
        HStack(spacing: 10) {
            ProviderIcon(name: provider.name)
            Text(provider.name).font(.system(size: 12)).frame(width: 47, alignment: .leading)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("\(Display.tokens(provider.tokens)) tokens").font(.system(size: 11))
                        .foregroundStyle(palette.muted)
                    Spacer(minLength: 6)
                    Text(Display.money(provider.spendUsd)).font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                }
                if showBar {
                    ProgressView(
                        value: provider.fraction.isFinite ? min(max(provider.fraction, 0), 1) : 0
                    ).progressViewStyle(ThinProgressStyle()).tint(palette.provider(provider.name))
                }
            }
        }
    }
}

struct StatusDot: View {
    @Environment(\.catsPalette) private var palette
    let status: String
    var body: some View {
        Image(systemName: palette.status(status).0).font(.system(size: 9, weight: .medium))
            .foregroundStyle(palette.status(status).1).frame(width: 11).accessibilityLabel(status)
    }
}

struct AgentRow: View {
    @Environment(\.catsPalette) private var palette
    let agent: Agent
    var showSpend = true
    var body: some View {
        HStack(spacing: 9) {
            StatusDot(status: agent.status)
            Text(agent.name).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 3)
            Text(agent.provider).foregroundStyle(palette.muted).frame(
                width: 44, alignment: .leading)
            Text(agent.elapsedSeconds == 0 ? "—" : Display.runtime(agent.elapsedSeconds))
                .foregroundStyle(palette.muted).frame(width: 32, alignment: .trailing)
            if showSpend {
                Text(Display.money(agent.spendUsd)).monospacedDigit().frame(
                    width: 49, alignment: .trailing)
            }
        }.font(.system(size: 11)).accessibilityElement(children: .combine)
    }
}

struct AgentCounts: View {
    @Environment(\.catsPalette) private var palette
    let state: TelemetryState
    var body: some View {
        HStack(spacing: 5) {
            StatusDot(status: "running")
            Text("\(state.activeAgents) running")
            Spacer(minLength: 8)
            StatusDot(status: state.failedAgents > 0 ? "failed" : "waiting")
            Text(
                state.failedAgents > 0
                    ? "\(state.failedAgents) failed" : "\(state.waitingAgents) waiting"
            ).foregroundStyle(palette.muted)
        }.font(.system(size: 11))
    }
}

struct Metric: View {
    @Environment(\.catsPalette) private var palette
    var title: String
    var value: String
    var icon: String? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            if let icon {
                Image(systemName: icon).font(.system(size: 15, weight: .light)).foregroundStyle(
                    palette.slate
                ).padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title).font(.system(size: 9)).foregroundStyle(palette.muted)
            }
        }
    }
}

struct Sparkline: View {
    @Environment(\.catsPalette) private var palette
    let values: [Double]
    var fill = false
    var body: some View {
        GeometryReader { geometry in
            let points = points(in: geometry.size)
            let line = Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for i in 1..<points.count {
                    let before = points[i - 1]
                    let after = points[i]
                    let middle = (before.x + after.x) / 2
                    path.addCurve(
                        to: after, control1: CGPoint(x: middle, y: before.y),
                        control2: CGPoint(x: middle, y: after.y))
                }
            }
            if fill {
                Path { path in
                    path.addPath(line)
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                    path.closeSubpath()
                }.fill(
                    LinearGradient(
                        colors: [palette.mint.opacity(0.20), palette.mint.opacity(0.01)],
                        startPoint: .top, endPoint: .bottom))
            }
            line.stroke(
                palette.mint, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
        }.accessibilityLabel("Spend over the past twelve hours")
    }
    private func points(in size: CGSize) -> [CGPoint] {
        let safe = values.map { $0.isFinite ? max($0, 0) : 0 }
        let peak = max(safe.max() ?? 0, 0.001)
        return safe.enumerated().map { i, value in
            CGPoint(
                x: size.width * Double(i) / Double(max(safe.count - 1, 1)),
                y: size.height - 3 - (size.height - 8) * value / peak)
        }
    }
}

struct StatusFooter: View {
    @Environment(\.catsPalette) private var palette
    let reading: SnapshotReading
    var body: some View {
        HStack(spacing: 4) {
            if reading.invalid {
                Image(systemName: "exclamationmark.triangle")
                Text("Snapshot unreadable")
            } else if reading.unavailable {
                Image(systemName: "clock")
                Text("Collector unavailable")
            } else if reading.state.collectorErrors > 0 {
                Image(systemName: "exclamationmark.triangle")
                Text("A source needs attention")
            } else if reading.state.today.unpricedEvents > 0 {
                Text("Partial estimate · unknown pricing")
            } else {
                Text("Estimated spend")
            }
            Spacer(minLength: 0)
            if reading.state.generatedAt > 0 {
                Text(Date(timeIntervalSince1970: reading.state.generatedAt), style: .relative)
                    .lineLimit(1)
            }
        }.font(.system(size: 9)).foregroundStyle(palette.muted)
    }
}

struct EmptyTelemetry: View {
    @Environment(\.catsPalette) private var palette
    var unavailable = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Brand(subtitle: "Your AI workspace")
            Spacer(minLength: 0)
            Text(unavailable ? "Collector unavailable" : "No usage yet").font(
                .system(size: 15, weight: .medium))
            Text(
                unavailable
                    ? "Open Cats to start tracking." : "Start Claude or Codex\nto begin tracking."
            ).font(.system(size: 11)).foregroundStyle(palette.muted)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
