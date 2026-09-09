import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppState
    private var palette: CatsPalette { CatsPalette(colors: model.reading.state.theme?.colors ?? [:]) }
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Brand(subtitle: "Your AI workspace")
            ControlPanel(reading: model.reading, pause: { model.command("pause") }, resume: { model.command("resume") }, open: { openWindow(id: "cats"); NSApplication.shared.activate(ignoringOtherApps: true) })
            HStack {
                Button("Open Cats") { openWindow(id: "cats"); NSApplication.shared.activate(ignoringOtherApps: true) }
                Spacer()
                Button("Quit") { model.stop(); NSApplication.shared.terminate(nil) }.foregroundStyle(palette.muted)
            }.buttonStyle(.plain).font(.caption)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(palette.error) }
        }.padding(20).frame(width: 358).background { GlassSurface(radius: 20) }
            .catsTheme(model.reading.state.theme)
    }
}
