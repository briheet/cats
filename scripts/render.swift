import AppKit
import SwiftUI

@main struct Render {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let fixture = URL(fileURLWithPath: "macos/Tests/Fixtures/state.json")
        let state = try TelemetryState.decode(Data(contentsOf: fixture))
        let themes = try JSONDecoder().decode(
            [String: ThemeState].self,
            from: Data(contentsOf: URL(fileURLWithPath: "build/themes.json"))
        )
        let directory = URL(fileURLWithPath: "build/previews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["dark", "light", "nord", "rose-pine", "rose-pine-moon", "rose-pine-dawn"] {
            var preview = state
            preview.theme = themes[name]
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
    }
}
