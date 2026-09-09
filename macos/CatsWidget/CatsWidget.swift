import SwiftUI
import WidgetKit
import AppIntents

struct CatsEntry: TimelineEntry {
    var date: Date
    var reading: Reading
}
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CatsEntry { CatsEntry(date: .now, reading: Reading(state: .empty)) }
    func getSnapshot(in context: Context, completion: @escaping (CatsEntry) -> Void) { completion(CatsEntry(date: .now, reading: SharedStorage.read())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CatsEntry>) -> Void) {
        let now = Date()
        let reading = SharedStorage.read()
        completion(Timeline(entries: [CatsEntry(date: now, reading: reading)], policy: .after(now.addingTimeInterval(900))))
    }
}
struct WidgetContent: View {
    @Environment(\.widgetFamily) private var family
    let entry: CatsEntry
    var focus: WidgetFocus = .spend
    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                switch focus {
                case .spend: SmallWidgetView(reading: entry.reading)
                case .agents: SmallAgentsView(reading: entry.reading)
                case .burn: SmallBurnView(reading: entry.reading)
                }
            case .systemMedium:
                if focus == .agents { MediumAgentsView(reading: entry.reading) }
                else { MediumWidgetView(reading: entry.reading) }
            case .systemExtraLarge: WideOverviewView(reading: entry.reading)
            default: LargeWidgetView(reading: entry.reading)
            }
        }.padding(family == .systemSmall ? 14 : 16)
            .containerBackground(for: .widget) { GlassSurface() }
            .widgetURL(URL(string: "cats://open"))
            .catsTheme(entry.reading.state.theme)
    }
}
enum WidgetFocus { case spend, agents, burn }

struct CatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CatsWidget", provider: Provider()) { WidgetContent(entry: $0) }
            .configurationDisplayName("Cats").description("Your agents, at a glance. Spend, activity, and what needs attention.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
            .contentMarginsDisabled()
    }
}

struct CatsAgentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CatsAgentsWidget", provider: Provider()) { WidgetContent(entry: $0, focus: .agents) }
            .configurationDisplayName("Cats · Agents").description("Keep running and waiting agents in sight.")
            .supportedFamilies([.systemSmall, .systemMedium]).contentMarginsDisabled()
    }
}

struct CatsBurnWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CatsBurnWidget", provider: Provider()) { WidgetContent(entry: $0, focus: .burn) }
            .configurationDisplayName("Cats · Burn rate").description("Your recent spending pace, at a glance.")
            .supportedFamilies([.systemSmall]).contentMarginsDisabled()
    }
}

@main struct CatsWidgets: WidgetBundle {
    var body: some Widget { CatsWidget(); CatsAgentsWidget(); CatsBurnWidget() }
}
