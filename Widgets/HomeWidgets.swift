import RemaCore
import SwiftUI
import WidgetKit

struct DialWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "rema.dial", provider: DayProvider()) { entry in
            DialWidgetView(entry: entry)
                .appLanguage()
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Dial")
        .description("The day on a 24-hour dial and the next reminder.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct NextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "rema.next", provider: DayProvider()) { entry in
            NextWidgetView(entry: entry)
                .appLanguage()
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Next reminder")
        .description("What is next and how soon.")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "rema.today", provider: DayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .appLanguage()
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Today")
        .description("Today's reminders, mark them right on the widget.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct WidgetHairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
    }
}

private struct WidgetBackground: View {
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        if mode == .fullColor {
            Palette.panel
        } else {
            Color.clear
        }
    }
}

struct DialWidgetView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            WidgetDial(style: .lock, size: 64, hour: entry.content.nowHour, minute: entry.content.nowMinute, markers: entry.content.markers)
                .widgetAccentable()
        } else {
            VStack(spacing: 6) {
                WidgetDial(style: .small, size: 104, hour: entry.content.nowHour, minute: entry.content.nowMinute, markers: entry.content.markers)
                if let next = entry.content.next {
                    (Text(verbatim: next.time).font(.app(.jost, 12, weight: 600)).foregroundColor(Palette.accentText) + Text(verbatim: " \(next.title)"))
                        .font(.app(.golos, 12, weight: 600))
                        .lineLimit(1)
                    Text(verbatim: next.countdown)
                        .font(.app(.golos, 11))
                        .foregroundStyle(Palette.secondary)
                } else {
                    Text(verbatim: String(localized: "Nothing ahead", bundle: .app, locale: .app))
                        .font(.app(.golos, 12, weight: 600))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .foregroundStyle(Palette.text)
        }
    }
}

struct NextWidgetView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            if let next = entry.content.next {
                Label {
                    Text(verbatim: "\(next.time) · \(next.title)")
                } icon: {
                    Image(systemName: "clock")
                }
            } else {
                Text(verbatim: String(localized: "Nothing ahead", bundle: .app, locale: .app))
            }
        case .accessoryCircular:
            countdownRing
        case .accessoryRectangular:
            rectangular
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let next = entry.content.next {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: next.countdown)
                        .font(.app(.golos, 11, weight: 600))
                        .tracking(0.88)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.accentText)
                    Text(verbatim: next.time)
                        .font(.app(.jost, 40, weight: 500))
                        .lineBox(44, .jost, 40, weight: 500)
                    Text(verbatim: next.title)
                        .font(.app(.golos, 14, weight: 600))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if entry.laterToday > 0 {
                    Text(verbatim: String(localized: "\(entry.laterToday) more today", bundle: .app, locale: .app))
                        .font(.app(.golos, 12))
                        .foregroundStyle(Palette.secondary)
                }
            } else {
                Text(verbatim: String(localized: "Nothing ahead", bundle: .app, locale: .app))
                    .font(.app(.golos, 14, weight: 600))
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(Palette.text)
    }

    private var countdownRing: some View {
        let minutes = entry.minutesLeft ?? 0
        let progress = entry.minutesLeft == nil ? 0 : max(0.05, 1 - Double(min(minutes, 60)) / 60)
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(verbatim: entry.minutesLeft.map { $0 < 100 ? "\($0)" : "\($0 / 60)" } ?? "–")
                    .font(.app(.jost, 22, weight: 500))
                Text(verbatim: minutes < 100 ? String(localized: "min", bundle: .app, locale: .app) : String(localized: "h", bundle: .app, locale: .app))
                    .font(.app(.golos, 10, weight: 600))
                    .opacity(0.85)
            }
        }
        .padding(4)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let next = entry.content.next {
                Text(verbatim: next.time)
                    .font(.app(.jost, 20, weight: 500))
                Text(verbatim: next.title)
                    .font(.app(.golos, 13, weight: 600))
                    .lineLimit(1)
                if entry.laterToday > 0 {
                    Text(verbatim: String(localized: "\(entry.laterToday) more today", bundle: .app, locale: .app))
                        .font(.app(.golos, 12))
                        .opacity(0.8)
                }
            } else {
                Text(verbatim: String(localized: "Nothing ahead", bundle: .app, locale: .app))
                    .font(.app(.golos, 13, weight: 600))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TodayWidgetView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemLarge {
            large
        } else {
            medium
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            WidgetDial(style: .medium, size: 142, hour: entry.content.nowHour, minute: entry.content.nowMinute, markers: entry.content.markers)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: String(localized: "Today", bundle: .app, locale: .app))
                        .font(.app(.golos, 11, weight: 600))
                        .tracking(0.88)
                        .textCase(.uppercase)
                    Spacer(minLength: 4)
                    Text(verbatim: String(localized: "\(entry.doneCount) of \(entry.rows.count)", bundle: .app, locale: .app))
                        .font(.app(.golos, 11))
                }
                .foregroundStyle(Palette.secondary)
                .padding(.bottom, 4)
                let rows = Array(entry.openRows.prefix(3))
                if rows.isEmpty {
                    Text(verbatim: String(localized: "Nothing ahead", bundle: .app, locale: .app))
                        .font(.app(.golos, 13, weight: 600))
                        .foregroundStyle(Palette.secondary)
                        .padding(.top, 8)
                }
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Button(intent: ToggleReminderIntent(reminderID: row.reminderID, occurrence: row.occurrence, done: !row.done)) {
                            CheckBox(isOn: row.done, size: 20)
                        }
                        .buttonStyle(.plain)
                        Text(verbatim: row.time)
                            .font(.app(.jost, 15, weight: row.highlighted ? 600 : 500))
                            .foregroundStyle(row.highlighted ? Palette.accentText : Palette.text)
                        Text(verbatim: row.title)
                            .font(.app(.golos, 13, weight: row.highlighted ? 600 : 400))
                            .lineLimit(1)
                    }
                    .frame(height: 40)
                    if row.id != rows.last?.id {
                        WidgetHairline()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(Palette.text)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: entry.content.dateLine.capitalizedFirst(.app))
                    .font(.app(.jost, 20, weight: 500))
                Spacer(minLength: 4)
                Text(verbatim: String(localized: "\(entry.doneCount) of \(entry.rows.count)", bundle: .app, locale: .app))
                    .font(.app(.golos, 13))
                    .foregroundStyle(Palette.secondary)
            }
            GeometryReader { proxy in
                let fraction = entry.rows.isEmpty ? 0 : Double(entry.doneCount) / Double(entry.rows.count)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.track)
                        .insetShadow(Capsule(), Palette.segmentWell, blur: 2, y: 1)
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: max(fraction > 0 ? 8 : 0, proxy.size.width * fraction))
                }
            }
            .frame(height: 8)
            .padding(.top, 10)
            VStack(spacing: 0) {
                let open = entry.openRows
                let rows = Array((open.isEmpty ? entry.rows : open).prefix(5))
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        Text(verbatim: row.time)
                            .font(.app(.jost, 18, weight: row.highlighted ? 600 : 500))
                            .foregroundStyle(row.done ? Palette.secondary : (row.highlighted ? Palette.accentText : Palette.text))
                            .frame(width: 48, alignment: .leading)
                        Text(verbatim: row.title)
                            .font(.app(.golos, 15, weight: row.highlighted ? 600 : 400))
                            .strikethrough(row.done)
                            .foregroundStyle(row.done ? Palette.secondary : Palette.text)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(intent: ToggleReminderIntent(reminderID: row.reminderID, occurrence: row.occurrence, done: !row.done)) {
                            CheckBox(isOn: row.done)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(minHeight: 47)
                    if row.id != rows.last?.id {
                        WidgetHairline()
                    }
                }
                if open.count > rows.count {
                    Text(verbatim: String(localized: "\(open.count - rows.count) more today", bundle: .app, locale: .app))
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                if rows.isEmpty {
                    Text(verbatim: String(localized: "Nothing for today", bundle: .app, locale: .app))
                        .font(.app(.golos, 15, weight: 600))
                        .foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .padding(.top, 8)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                if let place = entry.placeLine {
                    footnote(place, icon: Icons.pin, color: Palette.secondary)
                }
                if let yearly = entry.yearlyLine {
                    footnote(yearly, icon: Icons.star, color: Palette.yearly)
                }
            }
            .padding(.top, 10)
        }
        .foregroundStyle(Palette.text)
    }

    private func footnote(_ text: String, icon: [String], color: Color) -> some View {
        HStack(spacing: 6) {
            Glyph(paths: icon, size: 14, lineWidth: 2.2, color: color)
            Text(verbatim: text)
                .font(.app(.golos, 13))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        }
    }
}
