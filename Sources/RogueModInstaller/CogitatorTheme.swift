import SwiftUI

// Native vector ornamentation: no external artwork or runtime assets required.
enum Forge {
    static let void = Color(red: 0.055, green: 0.065, blue: 0.063)
    static let panel = Color(red: 0.09, green: 0.105, blue: 0.10)
    static let brass = Color(red: 0.73, green: 0.59, blue: 0.36)
    static let parchment = Color(red: 0.91, green: 0.86, blue: 0.74)
    static let muted = Color(red: 0.65, green: 0.67, blue: 0.60)
    static let phosphor = Color(red: 0.56, green: 0.83, blue: 0.63)
    static let red = Color(red: 0.44, green: 0.12, blue: 0.12)
}

struct ForgeButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(Forge.parchment)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(prominent ? Forge.red : Forge.brass.opacity(configuration.isPressed ? 0.22 : 0.08))
            .overlay(Rectangle().stroke(Forge.brass.opacity(prominent ? 0.75 : 0.4), lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}

struct ForgePanel: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Forge.panel)
            .overlay(Rectangle().stroke(Forge.brass.opacity(0.3), lineWidth: 1))
            .overlay(alignment: .topLeading) { CornerMark() }
            .overlay(alignment: .bottomTrailing) { CornerMark().rotationEffect(.degrees(180)) }
    }
}
extension View {
    func forgePanel() -> some View { modifier(ForgePanel()) }
}
private struct CornerMark: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 14)); path.addLine(to: .zero)
            path.addLine(to: CGPoint(x: 14, y: 0))
        }.stroke(Forge.brass, lineWidth: 2).frame(width: 14, height: 14).allowsHitTesting(false)
    }
}

struct RiteHeading: View {
    let index: String
    let title: String
    var body: some View {
        HStack(spacing: 10) {
            Text(index).foregroundStyle(Forge.brass)
            Text(title.uppercased()).foregroundStyle(Forge.parchment).tracking(1.5)
        }.font(.system(size: 10, weight: .semibold, design: .monospaced))
    }
}

struct CogitatorBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Forge.panel, Forge.void, Color(red: 0.105, green: 0.065, blue: 0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Canvas { context, size in
                    var lines = Path()
                    for y in stride(from: 0.0, to: size.height, by: 4) {
                        lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(lines, with: .color(.black.opacity(0.12)), lineWidth: 1)
                }
            }.allowsHitTesting(false)
    }
}

struct MachineSigil: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                ForEach(0..<12) { tooth in
                    Rectangle().fill(Forge.brass)
                        .frame(width: side * 0.12, height: side * 0.17)
                        .offset(y: -side * 0.40)
                        .rotationEffect(.degrees(Double(tooth) * 30))
                }
                Circle().fill(Forge.void).padding(side * 0.14)
                Circle().stroke(Forge.brass, lineWidth: side * 0.04).padding(side * 0.14)
                // A divided skull suggests the Mechanicus' union of flesh and machine.
                SkullGlyph().fill(Forge.parchment).padding(side * 0.28)
                Ellipse().fill(Forge.void).frame(width: side * 0.12, height: side * 0.10)
                    .offset(x: -side * 0.10, y: -side * 0.035)
                Circle().fill(Forge.void).frame(width: side * 0.12, height: side * 0.12)
                    .offset(x: side * 0.10, y: -side * 0.035)
                ForEach(0..<4) { tooth in
                    Rectangle().fill(Forge.void).frame(width: side * 0.018, height: side * 0.065)
                        .offset(x: (CGFloat(tooth) - 1.5) * side * 0.065, y: side * 0.18)
                }
                Rectangle().fill(Forge.void).frame(width: side * 0.025, height: side * 0.46)
                Circle().stroke(Forge.phosphor, lineWidth: side * 0.025)
                    .frame(width: side * 0.12, height: side * 0.12).offset(x: side * 0.10, y: -side * 0.035)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.accessibilityHidden(true)
    }
}
private struct SkullGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        path.move(to: p(0.2, 0.72)); path.addLine(to: p(0.08, 0.5))
        path.addCurve(to: p(0.5, 0), control1: p(-0.12, 0.08), control2: p(0.14, 0))
        path.addCurve(to: p(0.92, 0.5), control1: p(0.86, 0), control2: p(1.12, 0.08))
        path.addLine(to: p(0.8, 0.72)); path.addLine(to: p(0.75, 0.98))
        path.addLine(to: p(0.25, 0.98)); path.closeSubpath()
        return path
    }
}
