import AppKit
import SwiftUI

struct CatsTypography {
    var family = "system"
    var size: CGFloat = 12
    var scale: CGFloat { min(20, max(10, size.isFinite ? size : 12)) / 12 }

    static let configured: Self = {
        let environment = ProcessInfo.processInfo.environment
        return Self(
            family: environment["CATS_FONT_FAMILY"] ?? "system",
            size: Double(environment["CATS_FONT_SIZE"] ?? "12") ?? 12)
    }()

    func font(size: CGFloat, weight: Font.Weight) -> Font {
        guard family != "system", let font = NSFont(name: family, size: size) else {
            return .system(size: size, weight: weight)
        }
        return .custom(font.fontName, fixedSize: size).weight(weight)
    }
}

private struct TypographyKey: EnvironmentKey {
    static let defaultValue = CatsTypography.configured
}

extension EnvironmentValues {
    var catsTypography: CatsTypography {
        get { self[TypographyKey.self] }
        set { self[TypographyKey.self] = newValue }
    }
}

private struct CatsFont: ViewModifier {
    @Environment(\.catsTypography) private var typography
    let size: CGFloat
    let weight: Font.Weight
    func body(content: Content) -> some View {
        content.font(typography.font(size: size, weight: weight))
    }
}

extension View {
    func catsFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(CatsFont(size: size, weight: weight))
    }
}
