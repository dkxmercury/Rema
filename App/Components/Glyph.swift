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
    static let close = ["M6.5 6.5l11 11M17.5 6.5l-11 11"]
    static let back = ["M14.5 6l-6 6 6 6"]
    static let chevron = ["M9.5 6l6 6-6 6"]
    static let repeatArrows = ["M17 3l3.5 3.5L17 10", "M4 12v-1.5A4 4 0 0 1 8 6.5h12.5", "M7 21l-3.5-3.5L7 14", "M20 12v1.5a4 4 0 0 1-4 4H3.5"]
    static let early = ["M4.5 12a7.5 7.5 0 1 0 2.2-5.3", "M4 4v3.5h3.5", "M12 8v4l2.5 1.5"]
    static let bell = ["M6.5 9.5a5.5 5.5 0 0 1 11 0c0 5 2.3 7 2.3 7H4.2s2.3-2 2.3-7z", "M10 20a2.2 2.2 0 0 0 4 0", "M3 5.5a8 8 0 0 1 2.2-3M21 5.5a8 8 0 0 0-2.2-3"]
    static let bolt = ["M13 2.5L5 13.5h6l-1 8 8-11h-6l1-8z"]
    static let note = ["M9 18V5.5l11-2V16", circle(6.5, 18, 2.5), circle(17.5, 16, 2.5)]
    static let play = ["M7 4.5v15l13-7.5z"]
    static let microphone = [rect(9, 3, 6, 11.5, 3), "M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"]
    static let sliders = ["M4 7h9M17 7h3M4 17h3M11 17h9", circle(15, 7, 2), circle(9, 17, 2)]
    static let cloudCheck = ["M7 18.5h10a4 4 0 0 0 .6-8A6 6 0 0 0 6.2 9.6 4.5 4.5 0 0 0 7 18.5z", "M9.5 13.8l2 2 3.5-3.6"]
    static let sun = [circle(12, 12, 4), "M12 2.5v2M12 19.5v2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M2.5 12h2M19.5 12h2M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4"]
    static let moon = ["M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"]
    static let vibration = [rect(7, 3.5, 10, 17, 2.5), "M3.5 9v6M20.5 9v6"]
    static let speaker = ["M4.5 9.5h3l4.5-4v13l-4.5-4h-3z", "M16 9a4 4 0 0 1 0 6M18.5 6.5a7.5 7.5 0 0 1 0 11"]
    static let home = ["M4 10.5L12 4l8 6.5V20H4z", "M10 20v-5h4v5"]
    static let work = [rect(3.5, 7.5, 17, 12, 2.5), "M9 7.5V5.5h6v2M3.5 12.5h17"]
    static let sport = ["M6.5 7v10M17.5 7v10M3.5 9.5v5M20.5 9.5v5M6.5 12h11"]
    static let nature = ["M12 21v-5", "M12 3l6 8h-3.5l4 5H5.5l4-5H6z"]
    static let shop = ["M3 4h2.5l2 11h10l2-8H7", circle(9.5, 19, 1.5), circle(16.5, 19, 1.5)]
    static let search = [circle(11, 11, 6.5), "M20 20l-4.2-4.2"]
    static let locate = ["M20 4L4 10.5l7 2.5 2.5 7z"]
    static let folder = ["M3.5 7.5a2 2 0 0 1 2-2h4l2 2.5h7a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"]
    static let globe = [circle(12, 12, 8.5), "M3.5 12h17M12 3.5c2.5 2.4 3.8 5.3 3.8 8.5s-1.3 6.1-3.8 8.5c-2.5-2.4-3.8-5.3-3.8-8.5s1.3-6.1 3.8-8.5z"]

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
    var lineWidth: CGFloat = 2
    var color: Color
    var filled = false

    var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / 24
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            for data in paths {
                let path = Path(svg: data).applying(transform)
                if filled {
                    context.fill(path, with: .color(color))
                } else {
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
