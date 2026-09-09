import SwiftUI

struct CatsPalette {
    var colors: [String: String] = [:]
    func color(_ key: String, fallback: Color) -> Color {
        guard let hex = colors[key], hex.count == 7, hex.first == "#",
              let rgb = UInt32(hex.dropFirst(), radix: 16) else { return fallback }
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
    var mint: Color { color("accent", fallback: Color(red: 0.20, green: 0.81, blue: 0.65)) }
    var teal: Color { color("secondary", fallback: Color(red: 0.32, green: 0.72, blue: 0.76)) }
    var coral: Color { color("claude", fallback: Color(red: 0.95, green: 0.49, blue: 0.45)) }
    var blue: Color { color("codex", fallback: Color(red: 0.30, green: 0.65, blue: 1)) }
    var slate: Color { color("muted", fallback: Color(red: 0.52, green: 0.59, blue: 0.75)) }
    var ink: Color { color("surface", fallback: Color(red: 0.055, green: 0.085, blue: 0.17)) }
    var text: Color { color("text", fallback: .primary) }
    var muted: Color { color("muted", fallback: .secondary) }
    var warning: Color { color("warning", fallback: .orange) }
    var error: Color { color("error", fallback: .red) }
    func surface(_ scheme: ColorScheme) -> Color { color("surface", fallback: scheme == .dark ? ink : Color(white: 0.96)) }
    func provider(_ name: String) -> Color { name == "Claude" ? coral : name == "Codex" ? blue : slate }
    func status(_ value: String) -> (String, Color) {
        switch value {
        case "running": return ("circle.fill", mint)
        case "waiting": return ("circle.dotted", slate)
        case "failed": return ("exclamationmark.circle.fill", error)
        default: return ("checkmark", slate)
        }
    }
}
private struct CatsPaletteKey: EnvironmentKey { static let defaultValue = CatsPalette() }
extension EnvironmentValues {
    var catsPalette: CatsPalette {
        get { self[CatsPaletteKey.self] }
        set { self[CatsPaletteKey.self] = newValue }
    }
}
private struct ThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var theme: ThemeState?
    func body(content: Content) -> some View {
        let palette = CatsPalette(colors: theme?.colors ?? [:])
        content.environment(\.catsPalette, palette)
            .environment(\.colorScheme, theme?.appearance == "dark" ? .dark : theme?.appearance == "light" ? .light : scheme)
            .foregroundStyle(palette.text).tint(palette.mint)
    }
}
extension View {
    func catsTheme(_ theme: ThemeState?) -> some View { modifier(ThemeModifier(theme: theme)) }
}

struct GlassSurface: View {
    @Environment(\.catsPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var radius: CGFloat = 24
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if reduceTransparency {
                shape.fill(palette.surface(scheme))
            } else {
                shape.fill(.ultraThinMaterial).opacity(0.48)
                shape.fill(palette.surface(scheme).opacity(scheme == .dark ? 0.48 : 0.30))
                shape.fill(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.035 : 0.22), .clear, palette.blue.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(contrast == .increased ? 0.7 : 0.32), .white.opacity(0.07), .white.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.65))
        .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.08), radius: 18, x: 0, y: 10)
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 18
    var radius: CGFloat = 24
    @ViewBuilder var content: Content
    var body: some View { content.padding(padding).background { GlassSurface(radius: radius) } }
}

struct GlassControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(.primary.opacity(configuration.isPressed ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.10), lineWidth: 0.5))
    }
}

struct GlassAction<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: Label
    var body: some View {
        if #available(macOS 26, *) {
            Button(action: action) { label.font(.system(size: 12, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 3) }.buttonStyle(.glass)
        } else { Button(action: action) { label }.buttonStyle(GlassControlStyle()) }
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(.primary.opacity(0.10)).frame(height: 0.5) }
}

// Code-drawn desktop backdrop, used only by the gallery and render tool.
struct PreviewBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: scheme == .dark
                    ? [Color(red: 0.22, green: 0.28, blue: 0.47), Color(red: 0.16, green: 0.23, blue: 0.43), Color(red: 0.11, green: 0.15, blue: 0.28)]
                    : [Color(red: 0.69, green: 0.76, blue: 0.91), Color(red: 0.80, green: 0.84, blue: 0.94), Color(red: 0.66, green: 0.74, blue: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse().fill(Color.indigo.opacity(0.40)).frame(width: geometry.size.width * 0.8, height: geometry.size.height * 0.6).blur(radius: 90).offset(x: geometry.size.width * 0.40, y: -geometry.size.height * 0.25)
                Ellipse().fill(Color.blue.opacity(0.17)).frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.3).blur(radius: 75).offset(x: -geometry.size.width * 0.30, y: geometry.size.height * 0.10)
                Path { p in
                    p.move(to: CGPoint(x: geometry.size.width * 0.32, y: geometry.size.height))
                    p.addCurve(to: CGPoint(x: geometry.size.width, y: 0), control1: CGPoint(x: geometry.size.width * 0.65, y: geometry.size.height * 0.28), control2: CGPoint(x: geometry.size.width * 0.97, y: geometry.size.height * 0.45))
                    p.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    p.closeSubpath()
                }.fill(LinearGradient(colors: [.white.opacity(0.08), .indigo.opacity(0.08), .clear], startPoint: .topTrailing, endPoint: .bottomLeading))
            }
        }.clipped()
    }
}
