import SwiftUI

enum DesktopCardKind: CaseIterable {
    case overview
    case providers

    var size: CGSize {
        switch self {
        case .overview: return CGSize(width: 340, height: 340)
        case .providers: return CGSize(width: 340, height: 170)
        }
    }
}

/// The same card composition is used by live panels and visual previews.
struct DesktopCard: View {
    let kind: DesktopCardKind
    let reading: SnapshotReading

    var body: some View {
        GlassCard {
            switch kind {
            case .overview: OverviewCardContent(reading: reading)
            case .providers: ProviderCardContent(reading: reading)
            }
        }
        .frame(width: kind.size.width, height: kind.size.height)
        .catsTheme(reading.state.theme)
    }
}
