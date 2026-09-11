import SwiftUI

struct MetricsCard: View {
    var reading: MetricsReading
    @Environment(\.catsPalette) private var palette
    private var state: MetricsState { reading.state }
    private func bytes(_ value: Double) -> String {
        guard value.isFinite && value >= 0 else { return "—" }
        if value >= 1_000_000_000 { return String(format: "%.1f GB", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1f MB", value / 1_000_000) }
        return String(format: "%.0f KB", value / 1_000)
    }
    private func percent(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0) } ?? "—"
    }
    private var network: MetricsState.Network? {
        state.networks.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cats Metrics").catsFont(size: 13, weight: .medium)
                Spacer()
                Text(
                    reading.unavailable
                        ? "Unavailable" : state.lowPowerMode ? "Low power" : "System"
                )
                .catsFont(size: 10).foregroundStyle(
                    reading.unavailable ? palette.warning : palette.muted)
            }
            Hairline()
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 9) {
                GridRow {
                    metric("CPU", percent(state.cpuPercent))
                    metric(
                        "Memory",
                        state.memory.map { "\(bytes($0.used)) / \(bytes($0.total))" } ?? "—")
                }
                GridRow {
                    metric(
                        "Network" + (network.map { " · \($0.interface)" } ?? ""),
                        network.map {
                            "↓ \($0.receivedPerSecond.map(bytes) ?? "—")/s  ↑ \($0.transmittedPerSecond.map(bytes) ?? "—")/s"
                        } ?? "—")
                    metric("Disk free", state.disk.map { bytes($0.available) } ?? "—")
                }
                GridRow {
                    metric(
                        "Battery"
                            + (state.battery?.charging == true
                                ? " · Charging" : state.battery?.pluggedIn == true ? " · AC" : ""),
                        percent(state.battery?.percent))
                    metric("Thermal", state.thermal?.rawValue.capitalized ?? "—")
                }
            }
        }
        .padding(18).frame(width: 340, height: 170)
        .background { GlassSurface() }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).catsFont(size: 10).foregroundStyle(palette.muted)
            Text(value).catsFont(size: 12, weight: .medium).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LiveMetricsCard: View {
    @ObservedObject var model: MetricsModel
    var body: some View {
        let scale = CatsTypography.configured.scale
        MetricsCard(reading: model.reading).catsTheme(model.reading.state.theme)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: 340 * scale, height: 170 * scale, alignment: .topLeading)
    }
}

struct MetricsMenu: View {
    @ObservedObject var model: MetricsModel
    var showDesktop: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiveMetricsCard(model: model)
            MetricsHistory(points: model.reading.state.history)
            if let memory = model.reading.state.memory {
                Text(String(format: "Swap used: %.2f GB", memory.swapUsed / 1_000_000_000))
                    .catsFont(size: 11)
            }
            if let error = model.error { Text(error).catsFont(size: 11) }
            HStack {
                Button("Show widgets", action: showDesktop)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }.buttonStyle(GlassControlStyle())
        }.padding(12).catsTheme(model.reading.state.theme)
    }
}

private struct MetricsHistory: View {
    var points: [MetricsState.Point]
    @Environment(\.catsPalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CPU · Last two minutes").catsFont(size: 10).foregroundStyle(palette.muted)
            GeometryReader { geometry in
                Path { path in
                    var connected = false
                    for (index, point) in points.enumerated() {
                        guard let cpu = point.cpuPercent else {
                            connected = false
                            continue
                        }
                        let position = CGPoint(
                            x: geometry.size.width * Double(index)
                                / Double(max(1, points.count - 1)),
                            y: geometry.size.height * (1 - cpu / 100))
                        if connected { path.addLine(to: position) } else { path.move(to: position) }
                        connected = true
                    }
                }.stroke(palette.mint, lineWidth: 1.5)
            }.frame(height: 32)
                .accessibilityLabel("CPU usage over the last two minutes")
        }
    }
}
