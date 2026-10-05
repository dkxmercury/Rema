import SwiftUI

func cssGradient(_ degrees: Double, _ colors: [Color]) -> LinearGradient {
    let radians = degrees * .pi / 180
    let dx = sin(radians)
    let dy = -cos(radians)
    let half = (abs(dx) + abs(dy)) / 2
    return LinearGradient(
        colors: colors,
        startPoint: UnitPoint(x: 0.5 - dx * half, y: 0.5 - dy * half),
        endPoint: UnitPoint(x: 0.5 + dx * half, y: 0.5 + dy * half)
    )
}

struct OutsideOf<Inner: Shape>: Shape {
    let inner: Inner
    let margin: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -margin, dy: -margin))
        path.addPath(inner.path(in: rect))
        return path
    }
}

struct InsetShadow<Outline: Shape>: View {
    let shape: Outline
    let color: Color
    var blur: CGFloat = 0
    var x: CGFloat = 0
    var y: CGFloat = 0

    var body: some View {
        OutsideOf(inner: shape, margin: blur * 3 + abs(x) + abs(y) + 4)
            .fill(color, style: FillStyle(eoFill: true))
            .offset(x: x, y: y)
            .blur(radius: blur / 2)
            .mask(shape)
            .allowsHitTesting(false)
    }
}

extension View {
    func insetShadow<Outline: Shape>(_ shape: Outline, _ color: Color, blur: CGFloat = 0, x: CGFloat = 0, y: CGFloat) -> some View {
        overlay(InsetShadow(shape: shape, color: color, blur: blur, x: x, y: y))
    }
}

struct PanelBackground: ViewModifier {
    var radius: CGFloat
    var near = Palette.panelShadowNear
    var far = Palette.panelShadowFar
    var farRadius: CGFloat = 10
    var farOffset: CGFloat = 8

    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
            shape
                .fill(
                    Palette.panel
                        .shadow(.drop(color: near, radius: 1, x: 0, y: 1))
                        .shadow(.drop(color: far, radius: farRadius, x: 0, y: farOffset))
                )
                .insetShadow(shape, Palette.panelHighlight, y: 1)
        }
    }
}

extension View {
    func panel(radius: CGFloat = 22) -> some View {
        modifier(PanelBackground(radius: radius))
    }

    func inputBar() -> some View {
        modifier(PanelBackground(radius: 18, near: Palette.barShadowNear, far: Palette.barShadowFar, farRadius: 12, farOffset: 10))
    }
}

struct RaisedCircle: View {
    var size: CGFloat = 44

    var body: some View {
        Circle()
            .fill(
                LinearGradient(colors: [Palette.raisedTop, Palette.raisedBottom], startPoint: .top, endPoint: .bottom)
                    .shadow(.drop(color: Palette.raisedShadowNear, radius: 1, x: 0, y: 1))
                    .shadow(.drop(color: Palette.raisedShadowFar, radius: 5, x: 0, y: 4))
            )
            .insetShadow(Circle(), Palette.raisedHighlight, y: 1)
            .frame(width: size, height: size)
    }
}

struct SectionLabel: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.app(.golos, 12, weight: 600))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Palette.secondary)
    }
}

struct UrgentBadge: View {
    var body: some View {
        Text("Urgent")
            .font(.app(.golos, 11, weight: 600))
            .tracking(0.66)
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 6, style: .circular).fill(Palette.urgent))
    }
}
