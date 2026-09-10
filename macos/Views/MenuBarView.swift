import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppState
    let showDesktop: () -> Void
    let showDashboard: () -> Void
    private var palette: CatsPalette {
        CatsPalette(colors: model.reading.state.theme?.colors ?? [:])
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Brand()
            ControlPanel(
                reading: model.reading, pause: { model.send(.pause) },
                resume: { model.send(.resume) }, open: { showDashboard() })
            HStack {
                Button("Show widgets") { showDesktop() }
                Button("Open Cats") { showDashboard() }
                Spacer()
                Button("Quit") {
                    model.stop()
                    NSApplication.shared.terminate(nil)
                }.foregroundStyle(palette.muted)
            }.buttonStyle(.plain).font(.caption)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(palette.error) }
        }.padding(20).frame(width: 358).background { GlassSurface(radius: 20) }
            .catsTheme(model.reading.state.theme)
    }
}
