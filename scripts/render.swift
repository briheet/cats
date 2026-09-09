import AppKit
import SwiftUI

@main struct Render {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let data = try Data(contentsOf: URL(fileURLWithPath: "macos/Tests/Fixtures/state.json"))
        var state = try WidgetState.decode(data)
        state.generatedAt = Date().timeIntervalSince1970
        let reading = Reading(state: state)
        let themes = try JSONDecoder().decode([String: ThemeState].self, from: Data(contentsOf: URL(fileURLWithPath: "build/themes.json")))
        for name in ["nord", "rose-pine", "rose-pine-moon", "rose-pine-dawn"] {
            let renderer = ImageRenderer(content: DesignGallery(reading: reading).catsTheme(themes[name]))
            renderer.scale = 1.5
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: URL(fileURLWithPath: "docs/preview-\(name).png"))
        }
        for (name, scheme) in [("dark", ColorScheme.dark), ("light", ColorScheme.light)] {
            let renderer = ImageRenderer(content: DesignGallery(reading: reading).environment(\.colorScheme, scheme))
            renderer.scale = 1.5
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: URL(fileURLWithPath: "docs/preview-\(name).png"))
        }
        let native = VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                tile(width: 170, height: 170) { SmallWidgetView(reading: reading) }
                tile(width: 170, height: 170) { SmallAgentsView(reading: reading) }
                tile(width: 170, height: 170) { SmallBurnView(reading: reading) }
            }
            HStack(spacing: 16) {
                tile(width: 360, height: 170) { MediumWidgetView(reading: reading) }
                tile(width: 360, height: 170) { MediumAgentsView(reading: reading) }
            }
            HStack(alignment: .top, spacing: 16) {
                tile(width: 360, height: 360) { LargeWidgetView(reading: reading) }
                VStack(spacing: 16) {
                    tile(width: 170, height: 170) { SmallWidgetView(reading: Reading(state: .empty)) }
                    tile(width: 170, height: 170) { SmallWidgetView(reading: Reading(state: .empty, unavailable: true)) }
                }
            }
        }.padding(24).background { PreviewBackdrop() }.environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: native)
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: "build/native-sizes.png"))
        }
    }
    @MainActor static func tile<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content().padding(14).frame(width: width, height: height).background { GlassSurface() }
    }
}
