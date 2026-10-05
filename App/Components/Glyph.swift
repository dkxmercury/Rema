import RemaCore
import SwiftUI

extension Path {
    init(svg data: String) {
        self.init()
        for segment in SVGPath.parse(data) {
            switch segment {
            case .move(let point):
                move(to: CGPoint(point))
            case .line(let point):
                addLine(to: CGPoint(point))
            case .cubic(let control1, let control2, let point):
                addCurve(to: CGPoint(point), control1: CGPoint(control1), control2: CGPoint(control2))
            case .quad(let control, let point):
                addQuadCurve(to: CGPoint(point), control: CGPoint(control))
            case .close:
                closeSubpath()
            }
        }
    }
}

extension CGPoint {
    init(_ point: SVGPoint) {
        self.init(x: point.x, y: point.y)
    }
}

enum Icons {
    static let calendar = [rect(3.5, 5, 17, 15.5, 3), "M3.5 10h17M8.5 3v4M15.5 3v4"]
    static let plus = ["M12 5v14M5 12h14"]
    static let pin = ["M12 21s-6.5-6.2-6.5-11.2a6.5 6.5 0 0 1 13 0C18.5 14.8 12 21 12 21z", circle(12, 9.8, 2.3)]
    static let star = ["M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8L3.5 9.7l5.9-.9z"]
    static let check = ["M5 12.5l4.5 4.5L19 7.5"]

    static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> String {
        "M\(cx - r) \(cy)a\(r) \(r) 0 1 0 \(2 * r) 0a\(r) \(r) 0 1 0 \(-2 * r) 0z"
    }

    static func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ r: Double) -> String {
        "M\(x + r) \(y)h\(width - 2 * r)a\(r) \(r) 0 0 1 \(r) \(r)v\(height - 2 * r)a\(r) \(r) 0 0 1 \(-r) \(r)h\(2 * r - width)a\(r) \(r) 0 0 1 \(-r) \(-r)v\(2 * r - height)a\(r) \(r) 0 0 1 \(r) \(-r)z"
    }
}

struct Glyph: View {
    let paths: [String]
    var size: CGFloat
    var lineWidth: CGFloat
    var color: Color

    var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / 24
            let style = StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round)
            for data in paths {
                context.stroke(Path(svg: data).applying(CGAffineTransform(scaleX: scale, y: scale)), with: .color(color), style: style)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
