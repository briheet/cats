import AppKit
import CoreText
import SwiftUI

@main struct Render {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        if let path = ProcessInfo.processInfo.environment["CATS_PREVIEW_FONT_PATH"] {
            guard
                CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, nil)
            else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        precondition(DesktopCardKind.enabled(in: [:]) == [.overview, .providers])
        for mask in 0..<(1 << DesktopCardKind.allCases.count) {
            let expected = DesktopCardKind.allCases.enumerated().compactMap { index, kind in
                mask & (1 << index) == 0 ? nil : kind
            }
            let selection = expected.map(\.rawValue).joined(separator: ",")
            precondition(DesktopCardKind.enabled(in: ["CATS_WIDGETS": selection]) == expected)
        }
        let fixture = URL(fileURLWithPath: "macos/Tests/Fixtures/state.json")
        var state = try TelemetryState.decode(Data(contentsOf: fixture))
        let now = Date().timeIntervalSince1970
        for index in state.agents.indices {
            state.agents[index].lastActivityAt = now - [15.0, 480, 35518, 90000][index % 4]
        }
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
        for name in ["dark", "light"] + themes.keys.sorted() {
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
        for size: CGFloat in [10, 16, 20] {
            for family in [
                "system", "Helvetica Neue", "MissingCatsFont", "JetBrainsMono Nerd Font",
            ] {
                let typography = CatsTypography(family: family, size: size)
                let renderer = ImageRenderer(
                    content: PreviewGallery(reading: SnapshotReading(state: state))
                        .environment(\.catsTypography, typography))
                renderer.scale = 1
                guard let tiff = renderer.nsImage?.tiffRepresentation,
                    let png = NSBitmapImageRep(data: tiff)?.representation(
                        using: .png, properties: [:])
                else { throw CocoaError(.fileWriteUnknown) }
                try png.write(
                    to: directory.appendingPathComponent("font-\(family)-\(Int(size)).png"))
            }
        }
        for opacity in [0.0, 0.5, 1.0] {
            let renderer = ImageRenderer(
                content: PreviewGallery(reading: SnapshotReading(state: state))
                    .environment(\.catsGlassOpacity, opacity))
            renderer.scale = 1
            guard let tiff = renderer.nsImage?.tiffRepresentation,
                let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: directory.appendingPathComponent("opacity-\(opacity).png"))
        }
        print("PASS: six variants, 64 selections, all built-in themes, font and opacity extremes")
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
