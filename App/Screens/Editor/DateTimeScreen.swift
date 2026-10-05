import RemaCore
import SwiftUI

struct DateTimeScreen: View {
    let now: Date
    let settings: Settings
    var calendar: Calendar = .current
    var locale: Locale = .current
    let onDone: (Date) -> Void
    let onClose: () -> Void

    @State private var day: Date
    @State private var hour: Int
    @State private var minute: Int
    @State private var weekStart: Date

    init(initial: Date, now: Date, settings: Settings, calendar: Calendar = .current, locale: Locale = .current, onDone: @escaping (Date) -> Void, onClose: @escaping () -> Void) {
        self.now = now
        self.settings = settings
        self.calendar = calendar
        self.locale = locale
        self.onDone = onDone
        self.onClose = onClose
        let parts = calendar.dateComponents([.hour, .minute], from: initial)
        let start = calendar.startOfDay(for: initial)
        _day = State(initialValue: start)
        _hour = State(initialValue: parts.hour ?? 9)
        _minute = State(initialValue: parts.minute ?? 0)
        _weekStart = State(initialValue: DateTimeScreen.monday(of: start, calendar: calendar))
    }

    private var selected: Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ScreenHeader(title: "Date and time", leading: .close, action: onClose)
                chips
                    .padding(.top, 14)
                week
                    .padding(.top, 14)
                TimeDrums(hour: $hour, minute: $minute)
                    .padding(.top, 12)
                summary
                    .padding(.top, 12)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 15)
            PrimaryBar(action: { onDone(selected) }) {
                Text("Done")
            }
        }
        .foregroundStyle(Palette.text)
    }

    private var presets: [(LocalizedStringKey, Date)] {
        let inHour = roundedUp(now.addingTimeInterval(3600))
        let evening = at(settings.evening, on: now)
        let tonight = evening > now ? evening : calendar.date(byAdding: .day, value: 1, to: evening) ?? evening
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let morning = at(settings.morning, on: tomorrow)
        let saturday = nextSaturday()
        return [
            ("In an hour", inHour),
            ("This evening", tonight),
            ("Tomorrow morning", morning),
            ("On Saturday", saturday),
        ]
    }

    private var chips: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(presets.enumerated()), id: \.offset) { index, preset in
                Chip(title: preset.0, selected: isPresetSelected(index, preset.1)) {
                    apply(preset.1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isPresetSelected(_ index: Int, _ date: Date) -> Bool {
        if index == 2 {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.isDate(day, inSameDayAs: tomorrow) && (5..<12).contains(hour)
        }
        return calendar.isDate(selected, equalTo: date, toGranularity: .minute)
    }

    private var week: some View {
        VStack(spacing: 0) {
            HStack {
                weekArrow(Icons.back, "Previous week", -7)
                Spacer()
                Text(verbatim: monthTitle)
                    .font(.app(.jost, 17, weight: 500))
                    .contentTransition(.numericText())
                Spacer()
                weekArrow(Icons.chevron, "Next week", 7)
            }
            .padding(.bottom, 8)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { offset in
                    Text(verbatim: weekdaySymbol(offset))
                        .font(.app(.golos, 12, weight: 600))
                        .foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { offset in
                    dayCell(calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .panel()
    }

    private func weekArrow(_ icon: [String], _ label: LocalizedStringKey, _ days: Int) -> some View {
        Button {
            withAnimation(Motion.standard) {
                weekStart = calendar.date(byAdding: .day, value: days, to: weekStart) ?? weekStart
            }
        } label: {
            Glyph(paths: icon, size: 16, lineWidth: 2.2, color: Palette.text)
                .frame(width: 44, height: 36)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(label))
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: day)
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let isPast = date < calendar.startOfDay(for: now)
        let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
        return Button {
            withAnimation(Motion.small) { day = calendar.startOfDay(for: date) }
            Feedback.play(.select)
        } label: {
            VStack(spacing: 3) {
                Text(verbatim: "\(calendar.component(.day, from: date))")
                    .font(.app(.jost, 18, weight: isSelected ? 600 : 500))
                if isToday && !isSelected {
                    Circle().fill(Palette.text).frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(isSelected ? Palette.onAccent : (isPast ? Palette.faint : Palette.text))
            .frame(width: 44, height: 50)
            .background {
                if isSelected {
                    shape.fill(Palette.accent).insetShadow(shape, .black.opacity(0.14), y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isPast)
    }

    private var summary: some View {
        VStack(spacing: 0) {
            Text(verbatim: describer.fullDate(selected))
                .font(.app(.golos, 15, weight: 600))
                .contentTransition(.numericText())
            Text(verbatim: describer.countdown(from: now, to: selected))
                .font(.app(.golos, 13))
                .foregroundStyle(Palette.secondary)
                .contentTransition(.numericText())
        }
        .multilineTextAlignment(.center)
        .animation(Motion.standard, value: selected)
    }

    private var monthTitle: String {
        let reference = calendar.date(byAdding: .day, value: 3, to: weekStart) ?? weekStart
        return reference.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.wide).year()).capitalizedFirst(locale)
    }

    private func weekdaySymbol(_ offset: Int) -> String {
        var local = calendar
        local.locale = locale
        let symbols = local.shortStandaloneWeekdaySymbols
        return symbols[(offset + 1) % 7].capitalizedFirst(locale)
    }

    private func apply(_ date: Date) {
        withAnimation(Motion.standard) {
            day = calendar.startOfDay(for: date)
            weekStart = DateTimeScreen.monday(of: day, calendar: calendar)
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            hour = parts.hour ?? hour
            minute = parts.minute ?? minute
        }
        Feedback.play(.select)
    }

    private func at(_ time: LocalTime, on date: Date) -> Date {
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: date) ?? date
    }

    private func roundedUp(_ date: Date) -> Date {
        let parts = calendar.dateComponents([.minute], from: date)
        let minute = parts.minute ?? 0
        let add = (5 - minute % 5) % 5
        let rounded = calendar.date(byAdding: .minute, value: add, to: date) ?? date
        return calendar.date(bySetting: .second, value: 0, of: rounded) ?? rounded
    }

    private func nextSaturday() -> Date {
        var date = calendar.startOfDay(for: now)
        repeat {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        } while calendar.component(.weekday, from: date) != 7
        return at(settings.morning, on: date)
    }

    static func monday(of date: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let shift = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -shift, to: calendar.startOfDay(for: date)) ?? date
    }
}
