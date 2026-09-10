import AppKit
import SwiftUI

@main struct Render {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        precondition(DesktopCardKind.enabled(in: [:]) == [.overview, .providers])
        for mask in 0..<8 {
            let expected = DesktopCardKind.allCases.enumerated().compactMap { index, kind in
                mask & (1 << index) == 0 ? nil : kind
            }
            let selection = expected.map(\.rawValue).joined(separator: ",")
            precondition(DesktopCardKind.enabled(in: ["CATS_WIDGETS": selection]) == expected)
        }
        let fixture = URL(fileURLWithPath: "macos/Tests/Fixtures/state.json")
        let state = try TelemetryState.decode(Data(contentsOf: fixture))
        let themes = try JSONDecoder().decode(
            [String: ThemeState].self,
            from: Data(contentsOf: URL(fileURLWithPath: "build/themes.json"))
        )
        let directory = URL(fileURLWithPath: "build/previews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for count in [0, 1, 3, 5, 8] {
            var preview = state
            preview.theme = themes["nord"]
            preview.agents = (0..<count).map { index in
                var agent = state.agents[index % state.agents.count]
                agent.id = "preview-\(index)"
                agent.name = "agent-\(index + 1)"
                return agent
            }
            preview.activeAgents = preview.agents.filter { $0.status == "running" }.count
            preview.waitingAgents = preview.agents.filter { $0.status == "waiting" }.count
            if count == 0 { preview = TelemetryState(theme: themes["nord"]) }
            let renderer = ImageRenderer(
                content: DesktopCard(
                    kind: .overview,
                    reading: SnapshotReading(state: preview)
                ).padding(24).background { PreviewBackdrop() })
            renderer.scale = 2
            guard let tiff = renderer.nsImage?.tiffRepresentation,
                let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: directory.appendingPathComponent("agents-\(count).png"))
        }
        for name in ["dark", "light", "nord", "rose-pine", "rose-pine-moon", "rose-pine-dawn"] {
            var preview = state
            preview.theme = themes[name]
            for kind in DesktopCardKind.allCases {
                try checkCorners(kind: kind, reading: SnapshotReading(state: preview))
            }
            let content = PreviewGallery(reading: SnapshotReading(state: preview))
                .environment(\.colorScheme, name == "light" ? .light : .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                let tiff = image.tiffRepresentation,
                let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        print("PASS: transparent corners for all three desktop cards in all six themes")
    }

    @MainActor private static func checkCorners(kind: DesktopCardKind, reading: SnapshotReading)
        throws
    {
        let renderer = ImageRenderer(content: DesktopCard(kind: kind, reading: reading))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else { throw CocoaError(.fileReadCorruptFile) }
        for x in [0, bitmap.pixelsWide - 1] {
            for y in [0, bitmap.pixelsHigh - 1] {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent == 0 else {
                    throw NSError(
                        domain: "CatsPreview", code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Desktop card corner is not transparent"
                        ])
                }
            }
        }
        guard let center = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2),
            center.alphaComponent > 0
        else { throw CocoaError(.fileReadCorruptFile) }
    }
}
