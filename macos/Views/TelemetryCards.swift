import SwiftUI

struct SmallCardContent: View {
    @Environment(\.catsPalette) private var palette
    let reading: SnapshotReading

    var body: some View {
        let diameter: CGFloat = reading.warning == nil ? 92 : 80
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cats").catsFont(size: 13, weight: .semibold)
                Spacer()
                Text("Today").catsFont(size: 11).foregroundStyle(palette.muted)
            }
            ZStack {
                Circle().stroke(palette.muted.opacity(0.18), lineWidth: 6)
                Circle().trim(from: 0, to: min(max(reading.state.today.budgetFraction, 0), 1))
                    .stroke(
                        reading.state.today.budgetFraction > 1 ? palette.error : palette.mint,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Spend(value: reading.state.today.spendUsd, size: 21)
                    Text("of \(Display.money(reading.state.today.budgetUsd))")
                        .catsFont(size: 9).foregroundStyle(palette.muted)
                }
            }.frame(width: diameter, height: diameter).frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Estimated spend and daily budget")
            if reading.warning != nil {
                StatusFooter(reading: reading)
            } else {
                Text("\(reading.state.activeAgents) running")
                    .catsFont(size: 11).foregroundStyle(palette.muted)
            }
        }
    }
}

struct ProviderCardContent: View {
    @Environment(\.catsPalette) private var palette
    let reading: SnapshotReading
    var body: some View {
        if !reading.state.hasUsage {
            EmptyTelemetry(reading: reading)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Brand()
                    Spacer()
                    Text("Today").catsFont(size: 11).foregroundStyle(palette.muted)
                }
                Spacer(minLength: 5)
                VStack(spacing: 8) {
                    ForEach(reading.state.providers.prefix(2)) { ProviderRow(provider: $0) }
                }
                Spacer(minLength: 5)
                Hairline()
                if reading.warning != nil {
                    StatusFooter(reading: reading).padding(.top, 7)
                } else {
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
}

struct OverviewCardContent: View {
    @Environment(\.catsPalette) private var palette
    let reading: SnapshotReading

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Brand()
                Spacer()
                if reading.warning != nil {
                    StatusFooter(reading: reading)
                } else {
                    Text("Today · estimated spend").catsFont(size: 10)
                        .foregroundStyle(palette.muted)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                OverviewSection {
                    VStack(alignment: .leading, spacing: 8) {
                        Spend(value: reading.state.today.spendUsd, size: 28)
                        Text("of \(Display.money(reading.state.today.budgetUsd)) budget")
                            .catsFont(size: 10).foregroundStyle(palette.muted)
                        BudgetBar(today: reading.state.today)
                        Sparkline(values: reading.state.history.hourlySpend, fill: true)
                            .frame(height: 54)
                        Text("\(Display.money(reading.state.today.burnRatePerHour))/hr")
                            .catsFont(size: 11, weight: .medium)
                            .foregroundStyle(palette.muted)
                    }
                }.frame(width: 180)
                OverviewSection {
                    VStack(alignment: .leading, spacing: 6) {
                        AgentCounts(state: reading.state).padding(.bottom, 4)
                        if reading.state.agents.isEmpty {
                            Text("No recent agents").catsFont(size: 12)
                                .foregroundStyle(palette.muted).padding(.top, 12)
                        }
                        ForEach(reading.state.agents.prefix(5)) { agent in
                            AgentRow(agent: agent, showSpend: false).frame(height: 18)
                        }
                        if reading.state.agents.count > 5 {
                            Text("+\(reading.state.agents.count - 5) more in dashboard")
                                .catsFont(size: 9).foregroundStyle(palette.muted)
                        }
                    }
                }.frame(width: 300)
                OverviewSection {
                    VStack(alignment: .leading, spacing: 10) {
                        if reading.state.providers.isEmpty {
                            Text("No provider usage yet").catsFont(size: 11)
                                .foregroundStyle(palette.muted)
                        }
                        ForEach(reading.state.providers.prefix(2)) { provider in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(provider.name)
                                    Spacer()
                                    Text(Display.money(provider.spendUsd)).monospacedDigit()
                                }.catsFont(size: 11)
                                ProgressView(value: min(max(provider.fraction, 0), 1))
                                    .progressViewStyle(ThinProgressStyle(height: 5))
                                    .tint(palette.provider(provider.name))
                                Text("\(Display.tokens(provider.tokens)) tokens")
                                    .catsFont(size: 9).foregroundStyle(palette.muted)
                            }
                        }
                        Hairline()
                        Text("\(Display.tokens(reading.state.today.tokensTotal)) tokens today")
                            .catsFont(size: 11, weight: .medium)
                    }
                }
            }
        }
    }
}

private struct OverviewSection<Content: View>: View {
    @Environment(\.catsPalette) private var palette
    @ViewBuilder var content: Content

    var body: some View {
        content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(palette.ink.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(palette.muted.opacity(0.16), lineWidth: 0.5))
    }
}

struct BudgetPanel: View {
    @Environment(\.catsPalette) private var palette
    let today: TelemetryState.Today
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Budget").catsFont(size: 13, weight: .medium)
                Spacer()
                Text("Daily limit").catsFont(size: 11).foregroundStyle(palette.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Spend(value: today.spendUsd, size: 28)
                Text(
                    "/ \(Display.money(today.budgetUsd).replacingOccurrences(of: ".00", with: ""))"
                ).catsFont(size: 21, weight: .light).foregroundStyle(palette.muted)
            }
            HStack(spacing: 10) {
                BudgetBar(today: today)
                Text(today.budgetFraction.formatted(.percent.precision(.fractionLength(0))))
                    .catsFont(size: 11).foregroundStyle(palette.muted)
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
                Text("\(reading.state.activeAgents) agents running").catsFont(
                    size: 12, weight: .medium)
                Spacer()
                Text(Display.money(reading.state.today.spendUsd)).catsFont(
                    size: 12, weight: .medium)
                Text("today").catsFont(size: 11).foregroundStyle(palette.muted)
            }
            ForEach(reading.state.agents.prefix(3)) { AgentRow(agent: $0, showSpend: false) }
            if reading.state.agents.isEmpty {
                Text("Your next session will appear here.").catsFont(size: 11).foregroundStyle(
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
