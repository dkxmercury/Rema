import ActivityKit
import RemaCore
import SwiftUI
import WidgetKit

struct ReminderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReminderActivity.self) { context in
            LockCard(state: context.state, reminderID: context.attributes.reminderID)
                .activityBackgroundTint(Palette.panel)
                .activitySystemActionForegroundColor(Palette.text)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 10) {
                        IslandDial(due: context.state.due)
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: time(context.state.due))
                                .font(.app(.jost, 24, weight: 500))
                            if context.state.urgent {
                                Text("urgent")
                                    .font(.app(.golos, 12, weight: 600))
                                    .foregroundStyle(Color(hex: 0xFF8E7A))
                            }
                        }
                    }
                    .foregroundStyle(Color(hex: 0xF1EFEA))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("in")
                            .font(.app(.golos, 12))
                            .foregroundStyle(Color(hex: 0xA8A29A))
                        Text(timerInterval: context.state.start...context.state.due, countsDown: true)
                            .font(.app(.jost, 24, weight: 500))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Palette.accentOnDark)
                            .frame(maxWidth: 110, alignment: .trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(verbatim: context.state.title)
                            .font(.app(.golos, 18, weight: 600))
                            .foregroundStyle(Color(hex: 0xF1EFEA))
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            Button(intent: CompleteActivityIntent(reminderID: id(context.attributes.reminderID), occurrence: context.state.due)) {
                                Text("Done")
                                    .font(.app(.golos, 15, weight: 600))
                                    .foregroundStyle(Palette.onAccent)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(Capsule().fill(Palette.accent))
                            }
                            .buttonStyle(.plain)
                            Button(intent: SnoozeActivityIntent(reminderID: id(context.attributes.reminderID), occurrence: context.state.due)) {
                                Text("In 10 minutes")
                                    .font(.app(.golos, 15, weight: 600))
                                    .foregroundStyle(Color(hex: 0xF1EFEA))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(Capsule().fill(Color(hex: 0x2A2927)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                IslandDial(due: context.state.due)
                    .frame(width: 24, height: 24)
            } compactTrailing: {
                Text(timerInterval: context.state.start...context.state.due, countsDown: true)
                    .font(.app(.jost, 15, weight: 500))
                    .monospacedDigit()
                    .foregroundStyle(Palette.accentOnDark)
                    .frame(maxWidth: 52)
            } minimal: {
                IslandDial(due: context.state.due)
                    .frame(width: 22, height: 22)
            }
            .keylineTint(Palette.accent)
        }
    }

    private func id(_ raw: String) -> UUID {
        UUID(uuidString: raw) ?? UUID()
    }

    private func time(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

private struct LockCard: View {
    let state: ReminderActivity.ContentState
    let reminderID: String

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                AppTile()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: state.title)
                        .font(.app(.golos, 16, weight: 600))
                        .lineLimit(1)
                    Text(verbatim: subtitle)
                        .font(.app(.golos, 12))
                        .foregroundStyle(Palette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(timerInterval: state.start...state.due, countsDown: true)
                    .font(.app(.jost, 24, weight: 500))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Palette.accentText)
                    .frame(maxWidth: 96, alignment: .trailing)
            }
            ProgressView(timerInterval: state.start...state.due, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(Palette.accent)
            HStack(spacing: 10) {
                Button(intent: CompleteActivityIntent(reminderID: UUID(uuidString: reminderID) ?? UUID(), occurrence: state.due)) {
                    let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
                    Text("Done")
                        .font(.app(.golos, 15, weight: 600))
                        .foregroundStyle(Palette.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(shape.fill(Palette.accent).insetShadow(shape, .black.opacity(0.15), y: -3))
                }
                .buttonStyle(.plain)
                Button(intent: SnoozeActivityIntent(reminderID: UUID(uuidString: reminderID) ?? UUID(), occurrence: state.due)) {
                    let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
                    Text("In 10 minutes")
                        .font(.app(.golos, 15, weight: 600))
                        .foregroundStyle(Palette.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            shape
                                .fill(LinearGradient(colors: [Palette.raisedTop, Palette.raisedBottom], startPoint: .top, endPoint: .bottom))
                                .insetShadow(shape, Palette.raisedHighlight, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .foregroundStyle(Palette.text)
    }

    private var subtitle: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: state.due)
        let time = String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        let at = String(localized: "at \(time)")
        return state.urgent ? "\(at) · \(String(localized: "urgent"))" : at
    }
}

private struct AppTile: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        ZStack {
            shape
                .fill(LinearGradient(colors: [Color(hex: 0xFBFAF8), Color(hex: 0xD6D2CB)], startPoint: UnitPoint(x: 0.33, y: 0.03), endPoint: UnitPoint(x: 0.67, y: 0.97)))
            Canvas { context, canvas in
                let scale = canvas.width / 48
                func disc(_ x: Double, _ y: Double, _ r: Double) -> Path {
                    Path(ellipseIn: CGRect(x: (x - r) * scale, y: (y - r) * scale, width: 2 * r * scale, height: 2 * r * scale))
                }
                context.fill(disc(24, 24, 17), with: .color(Color(hex: 0xFBFAF8)))
                context.stroke(disc(24, 24, 17), with: .color(Color(hex: 0x1C1B19, alpha: 0.18)), lineWidth: 1 * scale)
                for index in 0..<12 {
                    let bar = Path(CGRect(x: -0.6, y: -15.5, width: 1.2, height: 3))
                    let transform = CGAffineTransform(rotationAngle: Double(index) * 30 * .pi / 180)
                        .concatenating(CGAffineTransform(translationX: 24, y: 24))
                        .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    context.fill(bar.applying(transform), with: .color(Color(hex: 0x1C1B19)))
                }
                var hand = Path()
                hand.move(to: CGPoint(x: 26.2 * scale, y: 26.2 * scale))
                hand.addLine(to: CGPoint(x: 15.5 * scale, y: 15.5 * scale))
                context.stroke(hand, with: .color(Palette.accent), style: StrokeStyle(lineWidth: 2.6 * scale, lineCap: .round))
                context.fill(disc(24, 24, 2.6), with: .color(Color(hex: 0x1C1B19)))
            }
        }
    }
}

private struct IslandDial: View {
    let due: Date

    var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / 48
            func disc(_ x: Double, _ y: Double, _ r: Double) -> Path {
                Path(ellipseIn: CGRect(x: (x - r) * scale, y: (y - r) * scale, width: 2 * r * scale, height: 2 * r * scale))
            }
            context.fill(disc(24, 24, 21), with: .color(Color(hex: 0x1C1B19)))
            context.stroke(disc(24, 24, 21), with: .color(.white.opacity(0.22)), lineWidth: 1.5 * scale)
            for index in 0..<8 {
                let bar = Path(CGRect(x: -0.7, y: -17.5, width: 1.4, height: 3))
                let transform = CGAffineTransform(rotationAngle: Double(index) * 45 * .pi / 180)
                    .concatenating(CGAffineTransform(translationX: 24, y: 24))
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                context.fill(bar.applying(transform), with: .color(Color(hex: 0xF1EFEA, alpha: 0.6)))
            }
            let parts = Calendar.current.dateComponents([.hour, .minute], from: due)
            let angle = DialGeometry().angle(hour: parts.hour ?? 0, minute: parts.minute ?? 0) * .pi / 180
            var hand = Path()
            hand.move(to: CGPoint(x: 24 * scale, y: 24 * scale))
            hand.addLine(to: CGPoint(x: (24 + 13 * sin(angle)) * scale, y: (24 - 13 * cos(angle)) * scale))
            context.stroke(hand, with: .color(Palette.accent), style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
            context.fill(disc(24, 24, 2.4), with: .color(Color(hex: 0xF1EFEA)))
        }
    }
}
