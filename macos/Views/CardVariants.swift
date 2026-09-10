import SwiftUI

struct SmallAgentsCard: View {
    @Environment(\.catsPalette) private var palette
    let reading: SnapshotReading

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Brand()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(reading.state.activeAgents)").catsFont(size: 30, weight: .medium)
                    .monospacedDigit()
                Text("running").catsFont(size: 10).foregroundStyle(palette.muted)
            }
            Hairline()
            HStack {
                StatusDot(status: "waiting")
                Text("Waiting")
                Spacer()
                Text("\(reading.state.waitingAgents)").monospacedDigit()
            }.catsFont(size: 11)
            HStack {
                StatusDot(status: "failed", muted: reading.state.failedAgents == 0)
                Text("Failed")
                Spacer()
                Text("\(reading.state.failedAgents)").monospacedDigit()
            }.catsFont(size: 11)
            StatusFooter(reading: reading)
        }
    }
}

struct SmallBurnRateCard: View {
    @Environment(\.catsPalette) private var palette
    let reading: SnapshotReading

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Brand()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Spend(value: reading.state.today.burnRatePerHour, size: 25)
                Text("/hr").catsFont(size: 12).foregroundStyle(palette.muted)
            }
            Text("Last 30 minutes").catsFont(size: 9).foregroundStyle(palette.muted)
            Sparkline(values: reading.state.history.hourlySpend, fill: true)
                .frame(height: reading.warning == nil ? 42 : 24)
            StatusFooter(reading: reading)
        }
    }
}

struct MediumAgentsCard: View {
    @Environment(\.catsPalette) private var palette
    let reading: SnapshotReading

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Brand()
                Spacer()
                Text("\(reading.state.activeAgents) running").catsFont(size: 11)
                    .foregroundStyle(palette.mint)
            }
            Hairline()
            if reading.state.agents.isEmpty {
                Text("No recent agents").catsFont(size: 12).foregroundStyle(palette.muted)
                    .padding(.vertical, 16)
            }
            ForEach(reading.state.agents.prefix(4)) { agent in
                AgentRow(agent: agent, showSpend: false).frame(height: 17)
            }
            if reading.warning != nil {
                StatusFooter(reading: reading)
            } else if reading.state.agents.count > 4 {
                Text("+\(reading.state.agents.count - 4) more in dashboard")
                    .catsFont(size: 9).foregroundStyle(palette.muted)
            }
        }
    }
}
