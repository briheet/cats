import SwiftUI

// Code-drawn desktop backdrop, used only by the gallery and render tool.
struct PreviewBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: scheme == .dark
                        ? [
                            Color(red: 0.22, green: 0.28, blue: 0.47),
                            Color(red: 0.16, green: 0.23, blue: 0.43),
                            Color(red: 0.11, green: 0.15, blue: 0.28),
                        ]
                        : [
                            Color(red: 0.69, green: 0.76, blue: 0.91),
                            Color(red: 0.80, green: 0.84, blue: 0.94),
                            Color(red: 0.66, green: 0.74, blue: 0.88),
                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse().fill(Color.indigo.opacity(0.40)).frame(
                    width: geometry.size.width * 0.8, height: geometry.size.height * 0.6
                ).blur(radius: 90).offset(
                    x: geometry.size.width * 0.40, y: -geometry.size.height * 0.25)
                Ellipse().fill(Color.blue.opacity(0.17)).frame(
                    width: geometry.size.width * 0.6, height: geometry.size.height * 0.3
                ).blur(radius: 75).offset(
                    x: -geometry.size.width * 0.30, y: geometry.size.height * 0.10)
                Path { p in
                    p.move(to: CGPoint(x: geometry.size.width * 0.32, y: geometry.size.height))
                    p.addCurve(
                        to: CGPoint(x: geometry.size.width, y: 0),
                        control1: CGPoint(
                            x: geometry.size.width * 0.65, y: geometry.size.height * 0.28),
                        control2: CGPoint(
                            x: geometry.size.width * 0.97, y: geometry.size.height * 0.45))
                    p.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    p.closeSubpath()
                }.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.08), .indigo.opacity(0.08), .clear],
                        startPoint: .topTrailing, endPoint: .bottomLeading))
            }
        }.clipped()
    }
}
