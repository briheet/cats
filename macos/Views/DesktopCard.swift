import SwiftUI

enum DesktopCardKind: String, CaseIterable {
    case overview = "large"
    case providers = "medium"
    case small
    case mediumAgents = "medium-agents"
    case smallAgents = "small-agents"
    case smallBurnRate = "small-burn-rate"

    static func enabled(in environment: [String: String]) -> [Self] {
        let selected = (environment["CATS_LLM_WIDGETS"] ?? "large,medium").split(separator: ",")
        return selected.compactMap { Self(rawValue: String($0)) }.reduce(into: []) { result, kind in
            if !result.contains(kind) { result.append(kind) }
        }
    }

    var size: CGSize {
        switch self {
        case .overview: return CGSize(width: 760, height: 250)
        case .providers, .mediumAgents: return CGSize(width: 340, height: 170)
        case .small, .smallAgents, .smallBurnRate: return CGSize(width: 170, height: 170)
        }
    }
}

/// The same card composition is used by live panels and visual previews.
struct DesktopCard: View {
    private let cornerRadius: CGFloat = 24
    let kind: DesktopCardKind
    let reading: SnapshotReading
    @Environment(\.catsTypography) private var typography

    var body: some View {
        Group {
            switch kind {
            case .overview: OverviewCardContent(reading: reading)
            case .providers: ProviderCardContent(reading: reading)
            case .small: SmallCardContent(reading: reading)
            case .mediumAgents: MediumAgentsCard(reading: reading)
            case .smallAgents: SmallAgentsCard(reading: reading)
            case .smallBurnRate: SmallBurnRateCard(reading: reading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .frame(width: kind.size.width, height: kind.size.height)
        .background { GlassSurface(radius: cornerRadius) }
        // Keep the glass and its shadow inside the rounded window silhouette.
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .catsTheme(reading.state.theme)
        .scaleEffect(typography.scale)
        .frame(
            width: kind.size.width * typography.scale, height: kind.size.height * typography.scale)
    }
}
