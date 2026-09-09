import SwiftUI

struct SmallWidgetView: View {
    @Environment(\.catsPalette) private var palette
    let reading: Reading
    var body: some View {
        if !reading.state.hasUsage { EmptyTelemetry(unavailable: reading.unavailable) }
        else {
            VStack(spacing: 8) {
                Brand(subtitle: "Today’s spend").frame(maxWidth: .infinity, alignment: .leading)
                BudgetRing(today: reading.state.today)
                VStack(spacing: 1) {
                    Text(reading.state.today.budgetFraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 12, weight: .medium))
                    Text(reading.unavailable ? "Collector unavailable" : reading.state.today.unpricedEvents > 0 ? "partial estimate" : "budget used")
                        .font(.system(size: 10)).foregroundStyle(palette.muted)
                }
            }
        }
    }
}

struct SmallAgentsView: View {
    @Environment(\.catsPalette) private var palette
    let reading: Reading
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Active agents").font(.system(size: 12, weight: .medium))
                Spacer()
                StatusDot(status: "running")
                Text("\(reading.state.activeAgents)").font(.system(size: 12, weight: .medium))
            }
            Hairline()
            ForEach(reading.state.providers.prefix(2)) { provider in
                countRow(provider.name, provider.agentCount ?? 0, palette.provider(provider.name))
            }
            countRow("Running", reading.state.activeAgents, palette.mint)
            countRow("Waiting", reading.state.waitingAgents, palette.slate, hollow: true)
            if reading.state.failedAgents > 0 { countRow("Failed", reading.state.failedAgents, palette.error) }
            Spacer(minLength: 0)
            if reading.unavailable { Text("Collector unavailable").font(.system(size: 9)).foregroundStyle(palette.muted) }
        }
    }
    private func countRow(_ title: String, _ count: Int, _ color: Color, hollow: Bool = false) -> some View {
        HStack(spacing: 9) {
            Image(systemName: hollow ? "circle.dotted" : "circle.fill").font(.system(size: 9)).foregroundStyle(color)
            Text(title).foregroundStyle(palette.muted)
            Spacer()
            Text("\(count)").monospacedDigit()
        }.font(.system(size: 12))
    }
}

struct SmallBurnView: View {
    @Environment(\.catsPalette) private var palette
    let reading: Reading
    var body: some View {
        if !reading.state.hasUsage { EmptyTelemetry(unavailable: reading.unavailable) }
        else {
            VStack(alignment: .leading, spacing: 10) {
                Brand(subtitle: "Burn rate")
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Spend(value: reading.state.today.burnRatePerHour, size: 28)
                    Text("/hr").font(.system(size: 22, weight: .light)).foregroundStyle(palette.muted)
                }.minimumScaleFactor(0.6)
                Text(reading.unavailable ? "Collector unavailable" : "Last 30 minutes").font(.system(size: 10)).foregroundStyle(palette.muted)
                Sparkline(values: reading.state.history.hourlySpend, fill: true).frame(minHeight: 25)
            }
        }
    }
}

struct MediumWidgetView: View {
    @Environment(\.catsPalette) private var palette
    let reading: Reading
    var body: some View {
        if !reading.state.hasUsage { EmptyTelemetry(unavailable: reading.unavailable) }
        else {
            VStack(spacing: 0) {
                HStack { Brand(subtitle: "Usage by provider"); Spacer(); Text("Today").font(.system(size: 11)).foregroundStyle(palette.muted) }
                Spacer(minLength: 5)
                VStack(spacing: 8) { ForEach(reading.state.providers.prefix(2)) { ProviderRow(provider: $0) } }
                Spacer(minLength: 5)
                Hairline()
                HStack {
                    Metric(title: "total tokens", value: Display.tokens(reading.state.today.tokensTotal), icon: "point.3.connected.trianglepath.dotted")
                    Spacer()
                    Metric(title: reading.unavailable ? "collector unavailable" : "burn rate", value: "\(Display.money(reading.state.today.burnRatePerHour))/hr", icon: "arrow.up")
                }.padding(.top, 7)
            }
        }
    }
}

struct MediumAgentsView: View {
    @Environment(\.catsPalette) private var palette
    let reading: Reading
    var body: some View {
        VStack(spacing: 7) {
            HStack { Text("Agents").font(.system(size: 13, weight: .medium)); Spacer(); Text("\(reading.state.activeAgents) active").font(.system(size: 11)).foregroundStyle(palette.muted) }
            ForEach(reading.state.agents.prefix(4)) { AgentRow(agent: $0, showSpend: false) }
            if reading.state.agents.isEmpty { Text("Your next session will appear here.").font(.system(size: 11)).foregroundStyle(palette.muted).frame(maxHeight: .infinity) }
            Hairline()
            HStack {
                Metric(title: "tokens today", value: Display.tokens(reading.state.today.tokensTotal))
                Spacer()
                Metric(title: "estimated spend", value: Display.money(reading.state.today.spendUsd))
                Spacer()
                Link(destination: URL(string: "cats://open")!) { HStack(spacing: 5) { Text("Open"); Image(systemName: "arrow.up.right") }.font(.system(size: 10)) }.buttonStyle(.plain)
            }
        }
    }
}

struct LargeWidgetView: View {
    @Environment(\.catsPalette) private var palette
    let reading: Reading
    var body: some View {
        if !reading.state.hasUsage && reading.state.agents.isEmpty { EmptyTelemetry(unavailable: reading.unavailable) }
        else {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Brand(subtitle: "Your AI workspace"); Spacer(); Spend(value: reading.state.today.spendUsd, size: 27) }
                HStack { Text("Spend today"); Spacer(); Text("of \(Display.money(reading.state.today.budgetUsd))") }.font(.system(size: 11)).foregroundStyle(palette.muted)
                BudgetBar(today: reading.state.today)
                Sparkline(values: reading.state.history.hourlySpend, fill: true).frame(height: 40)
                AgentCounts(state: reading.state)
                Hairline()
                ForEach(reading.state.agents.prefix(4)) { AgentRow(agent: $0) }
                Spacer(minLength: 0)
                HStack {
                    Metric(title: "tokens today", value: Display.tokens(reading.state.today.tokensTotal))
                    Spacer()
                    Metric(title: "burn rate", value: "\(Display.money(reading.state.today.burnRatePerHour))/hr")
                }
                StatusFooter(reading: reading)
            }
        }
    }
}

struct WideOverviewView: View {
    @Environment(\.catsPalette) private var palette
    let reading: Reading
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Brand(subtitle: "Your AI workspace")
                Spacer()
                Text("Today").font(.system(size: 11)).foregroundStyle(palette.muted)
                Image(systemName: "calendar").font(.system(size: 12)).foregroundStyle(palette.slate)
            }
            HStack(alignment: .top, spacing: 10) {
                inset {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Total spend").font(.system(size: 11, weight: .medium))
                        Spend(value: reading.state.today.spendUsd, size: 28)
                        Spacer(minLength: 0)
                        SpendBars(values: reading.state.history.hourlySpend).frame(minHeight: 30, maxHeight: 57)
                        HStack { Text("12 hours ago"); Spacer(); Text("Now") }.font(.system(size: 8)).foregroundStyle(palette.muted)
                    }
                }.frame(maxWidth: .infinity)
                inset {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack { Text("Agents").font(.system(size: 11, weight: .medium)); Spacer(); Text("\(reading.state.activeAgents) running").font(.system(size: 10)).foregroundStyle(palette.muted) }
                        ForEach(reading.state.agents.prefix(4)) { AgentRow(agent: $0, showSpend: false) }
                        Spacer(minLength: 0)
                        Link(destination: URL(string: "cats://open")!) {
                            Text("View all agents").font(.system(size: 10)).frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
                        }.buttonStyle(.plain)
                    }
                }.frame(maxWidth: .infinity)
                inset {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Usage by provider").font(.system(size: 11, weight: .medium))
                        ForEach(reading.state.providers.prefix(2)) { ProviderRow(provider: $0) }
                        Spacer(minLength: 0)
                        Hairline()
                        HStack {
                            Metric(title: "tokens today", value: Display.tokens(reading.state.today.tokensTotal))
                            Spacer()
                            Metric(title: "burn rate", value: "\(Display.money(reading.state.today.burnRatePerHour))/hr")
                        }
                    }
                }.frame(maxWidth: .infinity)
            }
            StatusFooter(reading: reading)
        }
    }
    private func inset<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(12).frame(maxHeight: .infinity, alignment: .topLeading)
            .background(.primary.opacity(0.015), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.09), lineWidth: 0.5))
    }
}

struct BudgetPanel: View {
    @Environment(\.catsPalette) private var palette
    let today: WidgetState.Today
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Budget").font(.system(size: 13, weight: .medium)); Spacer(); Text("Daily limit").font(.system(size: 11)).foregroundStyle(palette.muted) }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Spend(value: today.spendUsd, size: 28)
                Text("/ \(Display.money(today.budgetUsd).replacingOccurrences(of: ".00", with: ""))").font(.system(size: 21, weight: .light)).foregroundStyle(palette.muted)
            }
            HStack(spacing: 10) { BudgetBar(today: today); Text(today.budgetFraction.formatted(.percent.precision(.fractionLength(0)))).font(.system(size: 11)).foregroundStyle(palette.muted) }
            HStack {
                Metric(title: "projected by midnight", value: today.projectedDailySpend.map(Display.money) ?? "Not enough data")
                Spacer()
                Metric(title: "current burn", value: "\(Display.money(today.burnRatePerHour))/hr")
            }
        }
    }
}

struct ControlPanel: View {
    @Environment(\.catsPalette) private var palette
    let reading: Reading
    var pause: () -> Void = {}
    var resume: () -> Void = {}
    var open: () -> Void = {}
    var body: some View {
        VStack(spacing: 17) {
            HStack(spacing: 7) {
                StatusDot(status: "running")
                Text("\(reading.state.activeAgents) agents running").font(.system(size: 12, weight: .medium))
                Spacer()
                Text(Display.money(reading.state.today.spendUsd)).font(.system(size: 12, weight: .medium))
                Text("today").font(.system(size: 11)).foregroundStyle(palette.muted)
            }
            ForEach(reading.state.agents.prefix(3)) { AgentRow(agent: $0, showSpend: false) }
            if reading.state.agents.isEmpty { Text("Your next session will appear here.").font(.system(size: 11)).foregroundStyle(palette.muted) }
            Hairline()
            HStack(spacing: 8) {
                Button(action: pause) { Label("Pause agents", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                Button(action: resume) { Image(systemName: "play.fill") }.help("Resume Cats-managed agents")
                Button(action: open) { Image(systemName: "arrow.up.right") }.help("Open Cats")
            }.buttonStyle(GlassControlStyle())
            StatusFooter(reading: reading)
        }
    }
}
