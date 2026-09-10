import SwiftUI

enum DesktopCardKind: String, CaseIterable {
    case overview = "large"
    case providers = "medium"
    case small

    static func enabled(in environment: [String: String]) -> [Self] {
        let selected = (environment["CATS_WIDGETS"] ?? "large,medium").split(separator: ",")
        return allCases.filter { selected.contains(Substring($0.rawValue)) }
    }

    var size: CGSize {
        switch self {
        case .overview: return CGSize(width: 760, height: 250)
        case .providers: return CGSize(width: 340, height: 170)
        case .small: return CGSize(width: 170, height: 170)
        }
    }
}

/// The same card composition is used by live panels and visual previews.
struct DesktopCard: View {
    private let cornerRadius: CGFloat = 24
    let kind: DesktopCardKind
    let reading: SnapshotReading

    var body: some View {
        Group {
            switch kind {
            case .overview: OverviewCardContent(reading: reading)
            case .providers: ProviderCardContent(reading: reading)
            case .small: SmallCardContent(reading: reading)
            }
        }
        .padding(18)
        .frame(width: kind.size.width, height: kind.size.height)
        .background { GlassSurface(radius: cornerRadius) }
        // Keep the glass and its shadow inside the rounded window silhouette.
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .catsTheme(reading.state.theme)
    }
}
