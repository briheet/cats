import SwiftUI

struct DesignGallery: View {
    let reading: Reading
    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 20) {
                caption("Small widgets", "At a glance. Essential info.")
                HStack(spacing: 18) {
                    tile(width: 212, height: 232) { SmallWidgetView(reading: reading) }
                    tile(width: 212, height: 232) { SmallAgentsView(reading: reading) }
                    tile(width: 212, height: 232) { SmallBurnView(reading: reading) }
                }
                caption("Medium widgets", "More detail. Still glanceable.").padding(.top, 2)
                HStack(spacing: 18) {
                    tile(width: 408, height: 218) { MediumWidgetView(reading: reading) }
                    tile(width: 446, height: 218) { MediumAgentsView(reading: reading) }
                }
                caption("Workspace overview", "Everything together, without opening the app.").padding(.top, 2)
                tile(width: 872, height: 278) { WideOverviewView(reading: reading) }
            }
            VStack(alignment: .leading, spacing: 20) {
                caption("Menu bar / Control center", "Quick access, anywhere.")
                tile(width: 338, height: 56, padding: 14) {
                    HStack(spacing: 10) {
                        BrandMark(size: 26)
                        Text("Cats").font(.system(size: 14, weight: .medium))
                        Text(Display.money(reading.state.today.spendUsd)).font(.system(size: 14, weight: .medium))
                        Spacer()
                        StatusDot(status: "running")
                        Text("\(reading.state.activeAgents) agents").font(.system(size: 12)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.down").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                tile(width: 338, height: 256) { ControlPanel(reading: reading) }
                tile(width: 338, height: 208) { BudgetPanel(today: reading.state.today) }.padding(.top, 6)
                Spacer(minLength: 14)
                VStack(alignment: .leading, spacing: 12) {
                    BrandMark(size: 36)
                    Text("Keep your\nagents in sight.").font(.system(size: 28, weight: .medium)).foregroundStyle(.primary.opacity(0.65)).lineSpacing(2)
                    Text("Usage. Agents. Control.\nRight on your desktop.").font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
                }.padding(.leading, 12).padding(.top, 22)
                Spacer(minLength: 0)
            }.frame(width: 338)
        }.padding(36).background { PreviewBackdrop() }
    }
    private func caption(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 15, weight: .medium))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private func tile<Content: View>(width: CGFloat, height: CGFloat, padding: CGFloat = 18, @ViewBuilder content: () -> Content) -> some View {
        content().padding(padding).frame(width: width, height: height).background { GlassSurface() }
    }
}
