import RemaCore
import SwiftUI

struct DialMarker: Identifiable {
    enum Kind {
        case done
        case upcoming
        case next
        case missed
    }

    let id: Int
    let hour: Int
    let minute: Int
    let kind: Kind
    var reminderID: UUID?
    var occurrence: Date?
    var movable = false
}

struct DialLift: Equatable {
    let reminderID: UUID
    let occurrence: Date
    let original: Int
    var minutes: Int

    func holds(_ marker: DialMarker) -> Bool {
        marker.reminderID == reminderID && marker.occurrence == occurrence
    }
}

struct Dial: View {
    var size: CGFloat = 236
    var handMinutes: Double
    var markerProgress: Double = 1
    var markers: [DialMarker]
    var windowTime: String
    var windowCaption: String
    var windowFontSize: CGFloat = 17
    var windowTitleOnly = false
    var lift: DialLift?
    var badge: String?

    private let geometry = DialGeometry()

    var body: some View {
        let unit = size / 236
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(
                    cssGradient(160, [Palette.dialBezelTop, Palette.dialBezelBottom])
                        .shadow(.drop(color: Palette.dialShadowNear, radius: 2, x: 0, y: 2))
                        .shadow(.drop(color: Palette.dialShadowFar, radius: 16, x: 0, y: 16))
                )
                .insetShadow(Circle(), Palette.dialBezelHighlight, y: 1)
                .frame(width: size, height: size)

            Circle()
                .fill(Palette.dialFace)
                .insetShadow(Circle(), Palette.dialFaceShadow, blur: 6, y: 2)
                .frame(width: 212 * unit, height: 212 * unit)
                .offset(x: 12 * unit, y: 12 * unit)

            Canvas { context, canvas in
                draw(in: &context, scale: canvas.width / 280)
            }
            .frame(width: size, height: size)

            DialMarkersLayer(markers: markers, progress: markerProgress, lift: lift)
                .frame(width: size, height: size)
                .animation(.easeOut(duration: 0.7), value: markerProgress)

            DialHandLayer(minutes: handMinutes)
                .frame(width: size, height: size)
                .animation(Motion.hand, value: handMinutes)

            if let lift {
                let origin = geometry.point(angle: Double(lift.original) / 1440 * 360, radius: 133)
                DialLiftLayer(minutes: Double(lift.minutes), original: Double(lift.original))
                    .frame(width: size, height: size)
                    .animation(Motion.press, value: lift.minutes)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.4, anchor: UnitPoint(x: origin.x / 280, y: origin.y / 280)).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            window
                .frame(width: 100 * unit, height: 38 * unit)
                .offset(x: 68 * unit, y: 72 * unit)

            if let badge {
                Text(verbatim: badge)
                    .font(.app(.golos, 11, weight: 600))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)
                    .frame(width: 100 * unit, height: 20 * unit)
                    .background(RoundedRectangle(cornerRadius: 6, style: .circular).fill(Palette.urgent))
                    .offset(x: 68 * unit, y: 116 * unit)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var window: some View {
        RoundedRectangle(cornerRadius: 9, style: .circular)
            .fill(Palette.dialWindow)
            .insetShadow(RoundedRectangle(cornerRadius: 9, style: .circular), .black.opacity(0.45), blur: 4, y: 2)
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .circular)
                    .strokeBorder(Palette.dialWindowBorder, lineWidth: 1)
            }
            .overlay {
                VStack(spacing: 0) {
                    Text(verbatim: windowTime)
                        .font(.app(.jost, windowFontSize, weight: 500))
                        .tracking(windowTitleOnly ? windowFontSize * 0.02 : 0)
                        .foregroundStyle(Palette.dialWindowText)
                        .frame(height: max(19, windowFontSize + 2))
                        .contentTransition(.numericText())
                    if !windowTitleOnly {
                        Text(verbatim: windowCaption)
                            .font(.app(.golos, 10, weight: 600))
                            .foregroundStyle(Palette.accentOnDark)
                            .contentTransition(.numericText())
                    }
                }
                .animation(Motion.standard, value: windowTime)
                .animation(Motion.standard, value: windowCaption)
            }
    }

    private func draw(in context: inout GraphicsContext, scale: CGFloat) {
        func place(_ point: SVGPoint) -> CGPoint {
            CGPoint(x: point.x * scale, y: point.y * scale)
        }

        func tick(angle: Double, inner: Double, outer: Double, width: Double, color: Color) {
            let bar = Path(CGRect(x: -width / 2, y: -outer, width: width, height: outer - inner))
            let transform = CGAffineTransform(rotationAngle: angle * .pi / 180)
                .concatenating(CGAffineTransform(translationX: geometry.center, y: geometry.center))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            context.fill(bar.applying(transform), with: .color(color))
        }

        func dot(_ center: SVGPoint, radius: Double, color: Color) {
            let point = place(center)
            let r = radius * scale
            context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
        }

        for index in 0..<24 {
            tick(angle: Double(index) * 15, inner: 108, outer: 116, width: 1.4, color: Palette.dialTick.opacity(0.45))
        }
        for index in 0..<8 {
            tick(angle: Double(index) * 45, inner: 105, outer: 117, width: 3, color: Palette.dialTick)
        }

        for index in 0..<8 {
            let label = Text(verbatim: "\(index * 3)")
                .font(.app(.jost, 13 * scale, weight: 500))
                .foregroundColor(Palette.dialNumeral)
            context.draw(label, at: place(geometry.point(angle: Double(index) * 45, radius: 90)), anchor: .center)
        }

    }
}

private struct DialMarkersLayer: View, Animatable {
    let markers: [DialMarker]
    var progress: Double
    let lift: DialLift?

    private let geometry = DialGeometry()

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / 280
            let count = Double(max(markers.count, 1))
            let shown = markers.enumerated().compactMap { index, marker -> (marker: DialMarker, share: Double)? in
                let share = min(max(progress * (count + 1) - Double(index), 0), 1)
                guard share > 0, lift?.holds(marker) != true else { return nil }
                return (marker, share)
            }
            func place(_ minutes: Double) -> CGPoint {
                let center = geometry.point(angle: minutes / 1440 * 360, radius: 133)
                return CGPoint(x: center.x * scale, y: center.y * scale)
            }
            func minutes(_ marker: DialMarker) -> Double {
                Double(marker.hour * 60 + marker.minute)
            }
            // A busy stretch of the day would become a row of overlapping dots, neighbours are joined into one band.
            let plain = shown.filter { $0.marker.kind == .done || $0.marker.kind == .upcoming }.sorted { minutes($0.marker) < minutes($1.marker) }
            for (first, second) in zip(plain, plain.dropFirst()) where first.marker.kind == second.marker.kind {
                let start = minutes(first.marker)
                let end = minutes(second.marker)
                guard end > start, end - start <= 20 else { continue }
                let share = min(first.share, second.share)
                var band = Path()
                band.move(to: place(start))
                for step in 1...4 {
                    band.addLine(to: place(start + (end - start) * Double(step) / 4))
                }
                let color = first.marker.kind == .done ? Palette.dialDone : Palette.dialUpcoming
                context.stroke(band, with: .color(color.opacity(share)), style: StrokeStyle(lineWidth: 10 * scale * (0.6 + 0.4 * share), lineCap: .round, lineJoin: .round))
            }
            let layered = shown.filter { $0.marker.kind == .done || $0.marker.kind == .upcoming } + shown.filter { $0.marker.kind == .next || $0.marker.kind == .missed }
            for (marker, share) in layered {
                let point = place(minutes(marker))
                func dot(_ radius: Double, _ color: Color) {
                    let r = radius * scale * (0.6 + 0.4 * share)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r)), with: .color(color.opacity(share)))
                }
                switch marker.kind {
                case .done:
                    dot(5, Palette.dialDone)
                case .upcoming:
                    dot(5, Palette.dialUpcoming)
                case .next:
                    dot(7.5, Palette.dialNextRing)
                    dot(5.5, Palette.accent)
                case .missed:
                    dot(10, Palette.dialFace)
                    dot(8, Palette.urgent)
                    let mark = Text(verbatim: "!")
                        .font(.app(.golos, 12 * scale, weight: 700))
                        .foregroundColor(.white.opacity(share))
                    context.draw(mark, at: CGPoint(x: point.x, y: point.y + 0.5 * scale), anchor: .center)
                }
            }
        }
    }
}

private struct DialLiftLayer: View, Animatable {
    var minutes: Double
    let original: Double

    private let geometry = DialGeometry()

    var animatableData: Double {
        get { minutes }
        set { minutes = newValue }
    }

    var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / 280
            func place(_ value: Double) -> CGPoint {
                let point = geometry.point(angle: value / 1440 * 360, radius: 133)
                return CGPoint(x: point.x * scale, y: point.y * scale)
            }
            func circle(_ center: CGPoint, _ radius: Double) -> Path {
                let r = radius * scale
                return Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            }
            if abs(minutes - original) >= 1 {
                var arc = Path()
                let steps = max(Int(abs(minutes - original) / 2), 1)
                arc.move(to: place(original))
                for step in 1...steps {
                    arc.addLine(to: place(original + (minutes - original) * Double(step) / Double(steps)))
                }
                context.stroke(arc, with: .color(Palette.accent.opacity(0.7)), style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round, dash: [3 * scale, 5 * scale]))
            }
            let end = place(minutes)
            context.stroke(circle(place(original), 6), with: .color(Palette.accent.opacity(0.55)), lineWidth: 2 * scale)
            context.fill(circle(end, 17), with: .color(Palette.accent.opacity(0.18)))
            context.fill(circle(end, 9), with: .color(Palette.accent))
            context.stroke(circle(end, 9), with: .color(Palette.dialFace), lineWidth: 2.5 * scale)
            context.fill(circle(end, 25), with: .color(Palette.text.opacity(0.07)))
            context.stroke(circle(end, 25), with: .color(Palette.text.opacity(0.16)), lineWidth: 1.5 * scale)
        }
    }
}

private struct DialHandLayer: View, Animatable {
    var minutes: Double

    private let geometry = DialGeometry()

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
            func dot(_ radius: Double, _ color: Color) {
                let point = place(SVGPoint(geometry.center, geometry.center))
                let r = radius * scale
                context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
            }
            let angle = minutes / 1440 * 360
            var hand = Path()
            hand.move(to: place(geometry.point(angle: angle + 180, radius: 18)))
            hand.addLine(to: place(geometry.point(angle: angle, radius: 104)))
            context.stroke(hand, with: .color(Palette.accent), style: StrokeStyle(lineWidth: 3.2 * scale, lineCap: .round))
            dot(7, Palette.dialCap)
            dot(2.6, Palette.accent)
        }
    }
}
