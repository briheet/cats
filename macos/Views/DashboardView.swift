import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppState
    private var palette: CatsPalette {
        CatsPalette(colors: model.reading.state.theme?.colors ?? [:])
    }
    private var state: TelemetryState { model.reading.state }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center) {
                Brand(subtitle: "Your AI workspace")
                Spacer()
                HStack(spacing: 6) {
                    StatusDot(status: model.reading.unavailable ? "waiting" : "running")
                    Text(model.reading.unavailable ? "Collector offline" : "Tracking locally")
                        .font(.system(size: 11)).foregroundStyle(palette.muted)
                }
            }.padding(.top, 8)
            HStack(spacing: 18) {
                GlassCard { BudgetPanel(today: state.today).frame(height: 184) }
                GlassCard { ProviderCardContent(reading: model.reading).frame(height: 184) }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Agents").font(.system(size: 14, weight: .medium))
                        Spacer()
                        AgentCounts(state: state).frame(width: 235)
                    }
                    Hairline()
                    if state.agents.isEmpty {
                        VStack(spacing: 8) {
                            Text("Your next session starts here.").font(
                                .system(size: 14, weight: .medium))
                            Text("Start Claude, Codex, or a local agent.").font(.system(size: 12))
                                .foregroundStyle(palette.muted)
                        }.frame(maxWidth: .infinity, minHeight: 130)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 19) {
                                ForEach(state.agents) { AgentRow(agent: $0) }
                            }
                        }.frame(height: 130)
                    }
                    Hairline()
                    HStack {
                        Text("Managed agents").font(.system(size: 11)).foregroundStyle(
                            palette.muted
                        )
                        .help("Pause and resume apply to commands launched with cats run.")
                        Spacer()
                        GlassAction {
                            model.send(.pause)
                        } label: {
                            Label("Pause all", systemImage: "pause.fill")
                        }
                        GlassAction {
                            model.send(.resume)
                        } label: {
                            Label("Resume", systemImage: "play.fill")
                        }
                    }
                }
            }
            HStack {
                StatusFooter(reading: model.reading)
                if model.reading.unavailable {
                    Button("Start collector") { model.startCollector() }.font(.caption).buttonStyle(
                        .plain)
                }
            }.padding(.horizontal, 3)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(palette.error) }
        }.padding(26).frame(width: 820)
            .background(WindowBackdrop())
            .catsTheme(state.theme)
    }
}

private struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = WindowMaterialView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private final class WindowMaterialView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }
}
