import SwiftUI

struct ProviderCardContent: View {
    @Environment(\.catsPalette) private var palette
    let reading: SnapshotReading
    var body: some View {
        if !reading.state.hasUsage {
            EmptyTelemetry(unavailable: reading.unavailable)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Brand(subtitle: "Usage by provider")
                    Spacer()
                    Text("Today").font(.system(size: 11)).foregroundStyle(palette.muted)
                }
                Spacer(minLength: 5)
                VStack(spacing: 8) {
                    ForEach(reading.state.providers.prefix(2)) { ProviderRow(provider: $0) }
                }
                Spacer(minLength: 5)
                Hairline()
                HStack {
                    Metric(
                        title: "total tokens",
                        value: Display.tokens(reading.state.today.tokensTotal),
                        icon: "point.3.connected.trianglepath.dotted")
                    Spacer()
                    Metric(
                        title: reading.unavailable ? "collector unavailable" : "burn rate",
                        value: "\(Display.money(reading.state.today.burnRatePerHour))/hr",
                        icon: "arrow.up")
                }.padding(.top, 7)
            }
        }
    }
}

struct OverviewCardContent: View {
    @Environment(\.catsPalette) private var palette
    let reading: SnapshotReading
    var body: some View {
        if !reading.state.hasUsage && reading.state.agents.isEmpty {
            EmptyTelemetry(unavailable: reading.unavailable)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Brand(subtitle: "Your AI workspace")
                    Spacer()
                    Spend(value: reading.state.today.spendUsd, size: 27)
                }
                HStack {
                    Text("Spend today")
                    Spacer()
                    Text("of \(Display.money(reading.state.today.budgetUsd))")
                }.font(.system(size: 11)).foregroundStyle(palette.muted)
                BudgetBar(today: reading.state.today)
                Sparkline(values: reading.state.history.hourlySpend, fill: true).frame(height: 40)
                AgentCounts(state: reading.state)
                Hairline()
                ForEach(reading.state.agents.prefix(4)) { AgentRow(agent: $0) }
                Spacer(minLength: 0)
                HStack {
                    Metric(
                        title: "tokens today",
                        value: Display.tokens(reading.state.today.tokensTotal))
                    Spacer()
                    Metric(
                        title: "burn rate",
                        value: "\(Display.money(reading.state.today.burnRatePerHour))/hr")
                }
                StatusFooter(reading: reading)
            }
        }
    }
}

struct BudgetPanel: View {
    @Environment(\.catsPalette) private var palette
    let today: TelemetryState.Today
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Budget").font(.system(size: 13, weight: .medium))
                Spacer()
                Text("Daily limit").font(.system(size: 11)).foregroundStyle(palette.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Spend(value: today.spendUsd, size: 28)
                Text(
                    "/ \(Display.money(today.budgetUsd).replacingOccurrences(of: ".00", with: ""))"
                ).font(.system(size: 21, weight: .light)).foregroundStyle(palette.muted)
            }
            HStack(spacing: 10) {
                BudgetBar(today: today)
                Text(today.budgetFraction.formatted(.percent.precision(.fractionLength(0)))).font(
                    .system(size: 11)
                ).foregroundStyle(palette.muted)
            }
            HStack {
                Metric(
                    title: "projected by midnight",
                    value: today.projectedDailySpend.map(Display.money) ?? "Not enough data")
                Spacer()
                Metric(title: "current burn", value: "\(Display.money(today.burnRatePerHour))/hr")
            }
        }
    }
}

struct ControlPanel: View {
    @Environment(\.catsPalette) private var palette
    let reading: SnapshotReading
    var pause: () -> Void = {}
    var resume: () -> Void = {}
    var open: () -> Void = {}
    var body: some View {
        VStack(spacing: 17) {
            HStack(spacing: 7) {
                StatusDot(status: "running")
                Text("\(reading.state.activeAgents) agents running").font(
                    .system(size: 12, weight: .medium))
                Spacer()
                Text(Display.money(reading.state.today.spendUsd)).font(
                    .system(size: 12, weight: .medium))
                Text("today").font(.system(size: 11)).foregroundStyle(palette.muted)
            }
            ForEach(reading.state.agents.prefix(3)) { AgentRow(agent: $0, showSpend: false) }
            if reading.state.agents.isEmpty {
                Text("Your next session will appear here.").font(.system(size: 11)).foregroundStyle(
                    palette.muted)
            }
            Hairline()
            HStack(spacing: 8) {
                Button(action: pause) {
                    Label("Pause agents", systemImage: "pause.fill").frame(maxWidth: .infinity)
                }
                Button(action: resume) { Image(systemName: "play.fill") }.help(
                    "Resume Cats-managed agents")
                Button(action: open) { Image(systemName: "arrow.up.right") }.help("Open Cats")
            }.buttonStyle(GlassControlStyle())
            StatusFooter(reading: reading)
        }
    }
}
