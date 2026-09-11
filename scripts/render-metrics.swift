import AppKit
import SwiftUI

@main enum MetricsPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let themes = try JSONDecoder().decode(
            [String: ThemeState].self,
            from: Data(contentsOf: URL(fileURLWithPath: "build/themes.json")))
        var state = MetricsState()
        state.cpuPercent = 14
        state.memory = .init(used: 13_700_000_000, total: 24_000_000_000, swapUsed: 0)
        state.disk = .init(available: 192_000_000_000, total: 500_000_000_000)
        state.battery = .init(percent: 70, charging: false, pluggedIn: false)
        state.thermal = .nominal
        state.networks = [
            .init(interface: "en0", receivedPerSecond: 1_600_000, transmittedPerSecond: 35_000)
        ]
        for name in ["nord", "cats", "rose-pine", "gruvbox", "catppuccin-mocha"] {
            for size in [10.0, 12.0, 20.0] {
                let typography = CatsTypography(
                    family: size == 20 ? "MissingFont" : "system", size: size)
                let view = MetricsCard(reading: MetricsReading(state: state, unavailable: false))
                    .catsTheme(themes[name]).environment(\.catsTypography, typography)
                    .scaleEffect(typography.scale, anchor: .topLeading)
                    .frame(
                        width: 340 * typography.scale, height: 170 * typography.scale,
                        alignment: .topLeading)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let cgImage = renderer.cgImage,
                    let data = NSBitmapImageRep(cgImage: cgImage).representation(
                        using: .png, properties: [:])
                else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: URL(fileURLWithPath: "build/metrics-\(name)-\(Int(size)).png"))
            }
        }
        let renderer = ImageRenderer(
            content: MetricsCard(reading: MetricsReading()).catsTheme(themes["nord"]))
        renderer.scale = 2
        guard let image = renderer.cgImage,
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: URL(fileURLWithPath: "build/metrics-unavailable.png"))
    }
}
