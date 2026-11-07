import RemaCore
import SwiftUI

struct MiniDial: View, Animatable {
    var minutes: Double
    var size: CGFloat

    private let geometry = DialGeometry()

    init(hour: Int, minute: Int, size: CGFloat = 88) {
        minutes = Double(hour * 60 + minute)
        self.size = size
    }

    var animatableData: Double {
        get { minutes }
        set { minutes = newValue }
    }

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
            for index in 0..<12 {
                let bar = Path(CGRect(x: -2, y: -119, width: 4, height: 16))
                let transform = CGAffineTransform(rotationAngle: Double(index) * 30 * .pi / 180)
                    .concatenating(CGAffineTransform(translationX: geometry.center, y: geometry.center))
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                context.fill(bar.applying(transform), with: .color(Palette.dialTick.opacity(index % 3 == 0 ? 0.9 : 0.5)))
            }
            func hand(_ angle: Double, length: Double, width: Double, color: Color) {
                var path = Path()
                path.move(to: place(middle))
                path.addLine(to: place(geometry.point(angle: angle, radius: length)))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * scale, lineCap: .round))
            }
            hand(geometry.clockAngle(minutes: minutes), length: 62, width: 14, color: Palette.dialCap)
            hand(geometry.minuteAngle(minutes: minutes), length: 96, width: 8, color: Palette.accent)
            context.fill(disc(middle, 14), with: .color(Palette.dialCap))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
