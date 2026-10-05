import RemaCore
import SwiftUI

struct MiniDial: View {
    var hour: Int
    var minute: Int
    var size: CGFloat = 88

    private let geometry = DialGeometry()

    var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / 280
            func place(_ point: SVGPoint) -> CGPoint {
                CGPoint(x: point.x * scale, y: point.y * scale)
            }
            func disc(_ center: SVGPoint, _ radius: Double) -> Path {
                let point = place(center)
                let r = radius * scale
                return Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r))
            }
            let middle = SVGPoint(geometry.center, geometry.center)
            context.fill(disc(middle, 134), with: .color(Palette.miniFace))
            context.stroke(disc(middle, 132), with: .color(Palette.miniRim), lineWidth: 4 * scale)
            for index in 0..<24 {
                let bar = Path(CGRect(x: -1.5, y: -119, width: 3, height: 14))
                let transform = CGAffineTransform(rotationAngle: Double(index) * 15 * .pi / 180)
                    .concatenating(CGAffineTransform(translationX: geometry.center, y: geometry.center))
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                context.fill(bar.applying(transform), with: .color(Palette.dialTick.opacity(0.5)))
            }
            let angle = geometry.angle(hour: hour, minute: minute)
            var hand = Path()
            hand.move(to: place(middle))
            hand.addLine(to: place(geometry.point(angle: angle, radius: 93)))
            context.stroke(hand, with: .color(Palette.accent), style: StrokeStyle(lineWidth: 9 * scale, lineCap: .round))
            context.fill(disc(geometry.point(angle: angle, radius: 112), 15), with: .color(Palette.accent))
            context.fill(disc(middle, 14), with: .color(Palette.dialCap))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
