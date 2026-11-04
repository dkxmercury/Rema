import SwiftUI

struct AppIconTile: View {
    let choice: AppIconChoice
    var size: CGFloat = 72

    var body: some View {
        let look = choice.look
        let shape = RoundedRectangle(cornerRadius: (size * 0.23).rounded(), style: .continuous)
        shape
            .fill(
                cssGradient(160, [Color(hex: look.top), Color(hex: look.bottom)])
                    .shadow(.drop(color: Color(hex: look.lightBody ? 0x1C1B19 : 0x000000, alpha: look.lightBody ? 0.16 : 0.4), radius: 2, x: 0, y: 2))
                    .shadow(.drop(color: Color(hex: look.lightBody ? 0x1C1B19 : 0x000000, alpha: look.lightBody ? 0.12 : 0.25), radius: 11, x: 0, y: 10))
            )
            .insetShadow(shape, look.lightBody ? Color.white : Color.white.opacity(0.08), y: 1)
            .overlay {
                Canvas { context, canvas in
                    draw(look, in: &context, side: canvas.width)
                }
                .padding(size * 0.0625)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    // Coordinates are in the 48-point grid of the icon artwork.
    private func draw(_ look: AppIconChoice.Look, in context: inout GraphicsContext, side: CGFloat) {
        let unit = side / 48
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
        func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: (x - radius) * unit, y: (y - radius) * unit, width: radius * 2 * unit, height: radius * 2 * unit))
        }
        let ticks = Color(hex: look.ticks)
        let hand = Color(hex: look.hand)

        let face = circle(24, 24, 17)
        context.fill(face, with: .color(Color(hex: look.face)))
        context.stroke(face, with: .color(ticks.opacity(look.ring)), lineWidth: unit)

        var marks = Path()
        for index in 0..<12 {
            let angle = Double(index) * .pi / 6 - .pi / 2
            let center = CGPoint(x: 24 + 14 * cos(angle), y: 24 + 14 * sin(angle))
            let half = CGPoint(x: -sin(angle) * 0.6, y: cos(angle) * 0.6)
            marks.move(to: point(center.x - half.x, center.y - half.y))
            marks.addLine(to: point(center.x + half.x, center.y + half.y))
        }
        context.stroke(marks, with: .color(ticks), style: StrokeStyle(lineWidth: 3 * unit, lineCap: .butt))

        var needle = Path()
        needle.move(to: point(26.2, 26.2))
        needle.addLine(to: point(15.5, 15.5))
        context.stroke(needle, with: .color(hand), style: StrokeStyle(lineWidth: 2.6 * unit, lineCap: .round))

        context.fill(circle(24, 24, 2.6), with: .color(ticks))
        context.fill(circle(34, 6.7, 2.4), with: .color(hand))
    }
}
