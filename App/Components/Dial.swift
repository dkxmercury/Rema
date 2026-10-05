import RemaCore
import SwiftUI

struct DialMarker: Identifiable {
    enum Kind {
        case done
        case upcoming
        case next
    }

    let id: Int
    let hour: Int
    let minute: Int
    let kind: Kind
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

            DialMarkersLayer(markers: markers, progress: markerProgress)
                .frame(width: size, height: size)
                .animation(.easeOut(duration: 0.7), value: markerProgress)

            DialHandLayer(minutes: handMinutes)
                .frame(width: size, height: size)
                .animation(Motion.hand, value: handMinutes)

            window
                .frame(width: 100 * unit, height: 38 * unit)
                .offset(x: 68 * unit, y: 72 * unit)
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

    private let geometry = DialGeometry()

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / 280
            let count = Double(max(markers.count, 1))
            for (index, marker) in markers.enumerated() {
                let share = min(max(progress * (count + 1) - Double(index), 0), 1)
                guard share > 0 else { continue }
                let center = geometry.point(angle: geometry.angle(hour: marker.hour, minute: marker.minute), radius: 133)
                let point = CGPoint(x: center.x * scale, y: center.y * scale)
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
                }
            }
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
