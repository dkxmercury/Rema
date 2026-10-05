import RemaCore
import SwiftUI

struct WidgetDial: View {
    enum Style {
        case small
        case medium
        case lock
    }

    let style: Style
    let size: CGFloat
    let hour: Int
    let minute: Int
    let markers: [DialMarker]

    private let geometry = DialGeometry()

    var body: some View {
        ZStack {
            if style != .lock {
                Circle()
                    .fill(LinearGradient(colors: [Palette.dialBezelTop, Palette.dialBezelBottom], startPoint: UnitPoint(x: 0.33, y: 0.03), endPoint: UnitPoint(x: 0.67, y: 0.97)))
                    .shadow(color: Palette.dialShadowNear, radius: size * 0.06, y: size * 0.06)
                Circle()
                    .fill(Palette.dialFace)
                    .insetShadow(Circle(), Palette.dialFaceShadow, blur: 2, y: 1)
                    .padding(size * (style == .small ? 5 / 104 : 7 / 142))
            }
            Canvas { context, canvas in
                draw(in: context, scale: canvas.width / 280)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func draw(in context: GraphicsContext, scale: Double) {
        let ink = style == .lock ? Color.white : Palette.dialTick
        func place(_ point: SVGPoint) -> CGPoint {
            CGPoint(x: point.x * scale, y: point.y * scale)
        }
        func disc(_ point: SVGPoint, _ radius: Double) -> Path {
            let center = place(point)
            let r = radius * scale
            return Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        }
        let middle = SVGPoint(geometry.center, geometry.center)
        if style == .medium {
            ticks(context, count: 24, radius: 112, length: 9, width: 1.6, color: ink.opacity(0.45), scale: scale)
        }
        ticks(context, count: 8, radius: 111, length: style == .lock ? 16 : (style == .small ? 14 : 13), width: style == .lock ? 4 : (style == .small ? 3.5 : 3.2), color: style == .lock ? ink.opacity(0.85) : ink, scale: scale)

        for marker in markers where marker.kind != .next {
            let angle = geometry.angle(hour: marker.hour, minute: marker.minute)
            let color: Color = style == .lock ? .white.opacity(0.7) : (marker.kind == .done ? Palette.dialDone : Palette.dialUpcoming)
            context.fill(disc(geometry.point(angle: angle, radius: 133), style == .medium ? 7 : (style == .lock ? 9 : 8)), with: .color(color))
        }
        for marker in markers where marker.kind == .next {
            let angle = geometry.angle(hour: marker.hour, minute: marker.minute)
            let point = geometry.point(angle: angle, radius: 133)
            if style == .lock {
                context.fill(disc(point, 13), with: .color(.white))
            } else {
                let radius = style == .medium ? 9.5 : 11
                context.fill(disc(point, radius), with: .color(Palette.accent))
                context.stroke(disc(point, radius), with: .color(Palette.dialFace), lineWidth: (style == .medium ? 2.5 : 3) * scale)
            }
        }

        let angle = geometry.angle(hour: hour, minute: minute)
        var hand = Path()
        hand.move(to: place(geometry.point(angle: angle + 180, radius: 18)))
        hand.addLine(to: place(geometry.point(angle: angle, radius: 104)))
        let handWidth = style == .lock ? 9 : (style == .medium ? 5.5 : 7)
        context.stroke(hand, with: .color(style == .lock ? .white : Palette.accent), style: StrokeStyle(lineWidth: handWidth * scale, lineCap: .round))
        context.fill(disc(middle, style == .lock ? 14 : (style == .medium ? 11 : 13)), with: .color(style == .lock ? .white : Palette.dialCap))
        if style != .lock {
            context.fill(disc(middle, style == .medium ? 4.5 : 5), with: .color(Palette.accent))
        }
    }

    private func ticks(_ context: GraphicsContext, count: Int, radius: Double, length: Double, width: Double, color: Color, scale: Double) {
        for index in 0..<count {
            let bar = Path(CGRect(x: -width / 2, y: -radius - length / 2, width: width, height: length))
            let transform = CGAffineTransform(rotationAngle: Double(index) * (360 / Double(count)) * .pi / 180)
                .concatenating(CGAffineTransform(translationX: geometry.center, y: geometry.center))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            context.fill(bar.applying(transform), with: .color(color))
        }
    }
}
