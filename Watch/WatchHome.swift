import RemaCore
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum WatchPalette {
    static let accent = Color(hex: 0xF26A1B)
    static let accentText = Color(hex: 0xF7924F)
    static let ink = Color(hex: 0xF1EFEA)
    static let muted = Color(hex: 0xD9D5CE)
    static let faint = Color(hex: 0xA8A29A)
    static let done = Color(hex: 0x5F5B55)
    static let face = Color(hex: 0x161514)
    static let bezelTop = Color(hex: 0x3A3835)
    static let card = Color(hex: 0x1C1B19)
    static let urgent = Color(hex: 0xFF8E7A)
}

struct WatchHome: View {
    let model: WatchModel
    var moment: Date?

    var body: some View {
        if let moment {
            content(now: moment)
        } else {
            TimelineView(.everyMinute) { timeline in
                content(now: timeline.date)
            }
        }
    }

    private func content(now: Date) -> some View {
        let today = model.payload?.today(now, calendar: .current) ?? []
        let next = model.payload?.next(after: now)
        return ScrollView {
            VStack(spacing: 0) {
                WatchDial(now: now, items: model.payload?.ahead(now) ?? [], next: next)
                    .frame(width: 146, height: 146)
                if let next {
                    Text(verbatim: time(next.occurrence))
                        .font(.app(.jost, 22, weight: 500))
                        .foregroundStyle(WatchPalette.ink)
                        .padding(.top, 6)
                    Text(verbatim: next.title)
                        .font(.app(.golos, 13))
                        .foregroundStyle(WatchPalette.muted)
                        .lineLimit(1)
                    Text(verbatim: countdown(from: now, to: next.occurrence))
                        .font(.app(.golos, 12))
                        .foregroundStyle(WatchPalette.accentText)
                } else {
                    Text("Nothing ahead")
                        .font(.app(.golos, 13))
                        .foregroundStyle(WatchPalette.faint)
                        .padding(.top, 8)
                }
                if !today.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(today) { item in
                            row(item)
                        }
                    }
                    .padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.black)
    }

    private func row(_ item: WatchItem) -> some View {
        Button {
            model.toggle(item)
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: time(item.occurrence))
                    .font(.app(.jost, 15, weight: 500))
                    .foregroundStyle(item.done ? WatchPalette.done : WatchPalette.ink)
                Text(verbatim: item.title)
                    .font(.app(.golos, 13))
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? WatchPalette.done : (item.urgent ? WatchPalette.urgent : WatchPalette.ink))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle()
                        .strokeBorder(item.done ? Color.clear : WatchPalette.faint, lineWidth: 1.5)
                        .background(Circle().fill(item.done ? WatchPalette.accent : Color.clear))
                    if item.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: 0x1C1B19))
                    }
                }
                .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(WatchPalette.card))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.3), value: item.done)
    }

    private func time(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private func countdown(from now: Date, to date: Date) -> String {
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes < 60 {
            return String(localized: "in \(minutes) min", bundle: .app, locale: .app)
        }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? String(localized: "in \(hours) h", bundle: .app, locale: .app) : String(localized: "in \(hours) h \(rest) min", bundle: .app, locale: .app)
    }
}

struct WatchDial: View {
    let now: Date
    let items: [WatchItem]
    let next: WatchItem?

    private let geometry = DialGeometry()

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [WatchPalette.bezelTop, WatchPalette.face], startPoint: UnitPoint(x: 0.33, y: 0.03), endPoint: UnitPoint(x: 0.67, y: 0.97)))
            Circle()
                .fill(WatchPalette.face)
                .padding(7)
            Canvas { context, canvas in
                draw(context, scale: canvas.width / 280)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ context: GraphicsContext, scale: Double) {
        func place(_ point: SVGPoint) -> CGPoint {
            CGPoint(x: point.x * scale, y: point.y * scale)
        }
        func disc(_ point: SVGPoint, _ radius: Double) -> Path {
            let center = place(point)
            let r = radius * scale
            return Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        }
        ticks(context, count: 60, radius: 112, length: 7, width: 1.6, color: WatchPalette.ink.opacity(0.35), scale: scale)
        ticks(context, count: 12, radius: 111, length: 13, width: 3.2, color: WatchPalette.ink, scale: scale)
        let calendar = Calendar.current
        for item in items where item.id != next?.id {
            let parts = calendar.dateComponents([.hour, .minute], from: item.occurrence)
            let angle = geometry.clockAngle(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            context.fill(disc(geometry.point(angle: angle, radius: 133), 7), with: .color(WatchPalette.ink))
        }
        if let next, items.contains(where: { $0.id == next.id }) {
            let parts = calendar.dateComponents([.hour, .minute], from: next.occurrence)
            let point = geometry.point(angle: geometry.clockAngle(hour: parts.hour ?? 0, minute: parts.minute ?? 0), radius: 133)
            context.fill(disc(point, 9.5), with: .color(WatchPalette.accent))
            context.stroke(disc(point, 9.5), with: .color(WatchPalette.face), lineWidth: 2.5 * scale)
        }
        let clock = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = Double((clock.hour ?? 0) * 60 + (clock.minute ?? 0))
        func hand(_ angle: Double, length: Double, tail: Double, width: Double, color: Color) {
            var path = Path()
            path.move(to: place(geometry.point(angle: angle + 180, radius: tail)))
            path.addLine(to: place(geometry.point(angle: angle, radius: length)))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * scale, lineCap: .round))
        }
        hand(geometry.clockAngle(minutes: minutes), length: 62, tail: 12, width: 10, color: WatchPalette.ink)
        hand(geometry.minuteAngle(minutes: minutes), length: 100, tail: 18, width: 5.5, color: WatchPalette.accent)
        context.fill(disc(SVGPoint(geometry.center, geometry.center), 11), with: .color(WatchPalette.ink))
        context.fill(disc(SVGPoint(geometry.center, geometry.center), 4.5), with: .color(WatchPalette.accent))
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
