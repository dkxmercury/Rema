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
    static let list = ["M9 6.5h11M9 12h11M9 17.5h11", "M4.5 6.5h.01M4.5 12h.01M4.5 17.5h.01"]
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
    static let trash = ["M5 7h14", "M10 11v6M14 11v6", "M6.5 7l1 12.5a1.5 1.5 0 0 0 1.5 1.5h6a1.5 1.5 0 0 0 1.5-1.5L17.5 7", "M9.5 7V4.5h5V7"]
    static let folder = ["M3.5 7.5a2 2 0 0 1 2-2h4l2 2.5h7a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"]
    static let globe = [circle(12, 12, 8.5), "M3.5 12h17M12 3.5c2.5 2.4 3.8 5.3 3.8 8.5s-1.3 6.1-3.8 8.5c-2.5-2.4-3.8-5.3-3.8-8.5s1.3-6.1 3.8-8.5z"]
    static let chevronDown = ["M6 9.5l6 6 6-6"]
    static let envelope = [rect(3, 5.5, 18, 13, 2.5), "M3.5 7l8.5 6 8.5-6"]
    static let eye = ["M2.5 12c1-2 4.5-6.5 9.5-6.5s8.5 4.5 9.5 6.5c-1 2-4.5 6.5-9.5 6.5S3.5 14 2.5 12z", circle(12, 12, 3)]
    static let eyeOff = ["M3 3l18 18", "M10.6 5.6A9.6 9.6 0 0 1 12 5.5c5 0 8.5 4.5 9.5 6.5-.5 1-1.6 2.6-3.2 4M6.3 6.8C4.3 8.1 3 10 2.5 12c1 2 4.5 6.5 9.5 6.5 1.6 0 3-.4 4.3-1.1", "M9.9 10a3 3 0 0 0 4.1 4.1"]
    static let person = [circle(12, 8.5, 3.5), "M5 19.5c1.2-3.3 3.9-5 7-5s5.8 1.7 7 5"]
    static let clock = [circle(12, 12, 8.5), "M12 7.5V12l3 2"]
    static let instagram = [rect(3.5, 3.5, 17, 17, 5), circle(12, 12, 4), "M17 7h.01"]
    static let document = ["M7 3.5h7l4 4v13H7z", "M14 3.5v4h4", "M9.5 12h6M9.5 15.5h6"]
    static let insert = ["M17 17L7 7M7 15V7h8"]
    static let waveform = ["M4 12h2M8 8v8M12 5v14M16 8v8M20 12h-2"]
    static let widgets = [rect(4, 4, 7, 7, 2), rect(13, 4, 7, 7, 2), rect(4, 13, 7, 7, 2), rect(13, 13, 7, 7, 2)]
    static let island = [rect(4, 9, 16, 6, 3)]
    static let watch = [rect(7, 6, 10, 12, 3), "M9.5 6l.5-3h4l.5 3M9.5 18l.5 3h4l.5-3"]
    static let faceID = ["M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2", "M9 9.5v1M15 9.5v1M12 9.5v3.5h-1M9.5 15.5c1.4 1 3.6 1 5 0"]
    static let message = ["M4.5 6.5A2.5 2.5 0 0 1 7 4h10a2.5 2.5 0 0 1 2.5 2.5v7A2.5 2.5 0 0 1 17 16h-6l-4.5 4v-4h0A2.5 2.5 0 0 1 4.5 13.5z"]
    static let people = [circle(9, 8.5, 3.2), "M3.5 19.5c.6-3.3 2.7-5 5.5-5s4.9 1.7 5.5 5", circle(16.8, 9.5, 2.6), "M15.6 14.6c2.6-.3 4.4 1.3 4.9 4.4"]
    static let link = ["M10 14a4.5 4.5 0 0 0 6.4 0l2.8-2.8a4.5 4.5 0 0 0-6.4-6.4L11.6 6", "M14 10a4.5 4.5 0 0 0-6.4 0l-2.8 2.8a4.5 4.5 0 0 0 6.4 6.4l1.2-1.2"]
    static let flag = ["M5.5 21V4", "M5.5 4.5h11l-2 4 2 4h-11"]
    static let block = [circle(12, 12, 8.5), "M6 6l12 12"]
    static let exit = ["M14 4.5h4.5v15H14", "M10.5 8L6.5 12l4 4", "M6.5 12H16"]
    static let pen = ["M4.5 19.5l1-4 10-10 3 3-10 10-4 1z", "M13.5 7.5l3 3"]
    static let keyboard = [rect(3, 6.5, 18, 11, 2.5), "M7 10h.01M10.5 10h.01M14 10h.01M17.5 10h.01M8 14h8"]
    static let external = ["M10 5H5.5v13.5H19V14", "M13.5 4.5H19.5V10.5", "M19 5l-8 8"]

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
        .flipsForRightToLeftLayoutDirection([Icons.back, Icons.chevron, Icons.insert, Icons.list, Icons.external, Icons.exit].contains(paths))
        .accessibilityHidden(true)
    }
}
