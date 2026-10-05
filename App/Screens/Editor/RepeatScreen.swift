import RemaCore
import SwiftUI

struct RepeatScreen: View {
    @Binding var draft: Reminder
    var now: Date
    var calendar: Calendar
    var locale: Locale
    let onBack: () -> Void

    private enum Kind: CaseIterable {
        case once, daily, weekdays, weekly, everyDays, monthly, yearly
    }

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    private var schedule: Schedule {
        draft.schedule ?? Schedule(start: LocalDate(now, in: calendar), time: LocalTime(hour: 9, minute: 0))
    }

    private var kind: Kind {
        switch schedule.rule {
        case .none: return .once
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .weekly: return .weekly
        case .everyDays: return .everyDays
        case .monthlyOnDay, .monthlyOnWeekday: return .monthly
        case .yearly: return .yearly
        }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    ScreenHeader(title: "Repeat", leading: .back, action: onBack)
                    summary
                        .padding(.top, 14)
                    options
                        .padding(.top, 12)
                    PanelList {
                        endRow
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 18)
                .padding(.top, 15)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            PrimaryBar(action: onBack) {
                Text("Done")
            }
        }
        .foregroundStyle(Palette.text)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: draft.title.isEmpty ? String(localized: "New reminder") : draft.title)
                .font(.app(.golos, 13))
                .foregroundStyle(Palette.secondary)
            Text(verbatim: headline)
                .font(.app(.jost, 26, weight: 500))
                .lineBox(30, .jost, 26, weight: 500)
                .contentTransition(.opacity)
            FlowLayout(spacing: 6) {
                Text(verbatim: String(localized: "at \(describer.time(nextDates.first ?? now)), next"))
                    .font(.app(.golos, 13))
                    .foregroundStyle(Palette.secondary)
                    .frame(height: 24)
                ForEach(nextDates, id: \.self) { date in
                    Tag(text: shortDate(date))
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
        .animation(Motion.standard, value: schedule)
    }

    private var headline: String {
        guard let rule = schedule.rule else {
            return describer.fullDate(nextDates.first ?? now)
        }
        switch rule {
        case .yearly(let month, let day):
            return String(localized: "Every year, \(longDate(month: month, day: day))")
        default:
            return describer.repeatValue(schedule)
        }
    }

    private var nextDates: [Date] {
        Recurrence.next(schedule, after: now, limit: schedule.rule == nil ? 1 : 3, calendar: calendar)
    }

    private var options: some View {
        PanelList {
            ForEach(Array(Kind.allCases.enumerated()), id: \.offset) { index, option in
                optionRow(option)
                if index < Kind.allCases.count - 1 {
                    Hairline()
                }
            }
        }
    }

    private func optionRow(_ option: Kind) -> some View {
        let selected = option == kind
        return Button {
            select(option)
        } label: {
            HStack(spacing: 12) {
                RadioMark(isOn: selected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(option))
                        .font(.app(.golos, 16, weight: selected ? 600 : 400))
                    if selected, option == .yearly {
                        Text("for payments and birthdays")
                            .font(.app(.golos, 12))
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                detail(option, selected: selected)
            }
            .frame(minHeight: option == .yearly ? (selected ? 62 : 48) : 47)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func title(_ option: Kind) -> LocalizedStringKey {
        switch option {
        case .once: return "Once"
        case .daily: return "Every day"
        case .weekdays: return "On weekdays"
        case .weekly: return "On days of the week"
        case .everyDays: return "Every N days"
        case .monthly: return "Every month"
        case .yearly: return "Every year"
        }
    }

    @ViewBuilder
    private func detail(_ option: Kind, selected: Bool) -> some View {
        switch option {
        case .once, .daily:
            EmptyView()
        case .weekdays:
            detailText(describer.weekdayList([.monday, .tuesday, .wednesday, .thursday, .friday]), selected: false)
        case .weekly:
            if case .weekly(let days) = schedule.rule {
                detailText(describer.repeatText(.weekly(days)), selected: selected)
            } else {
                detailText(String(localized: "choose"), selected: false)
            }
        case .everyDays:
            if case .everyDays(let count) = schedule.rule {
                Stepper("", value: Binding(get: { count }, set: { setRule(.everyDays(max(2, $0))) }), in: 2...60)
                    .labelsHidden()
                    .fixedSize()
                Text(verbatim: describer.repeatText(.everyDays(count)))
                    .font(.app(.golos, 14, weight: 600))
            } else {
                detailText(describer.repeatText(.everyDays(3)), selected: false)
            }
        case .monthly:
            detailText(String(localized: "on day \(schedule.start.day)"), selected: selected)
        case .yearly:
            HStack(spacing: 12) {
                detailText(longDate(month: schedule.start.month, day: schedule.start.day), selected: selected)
                if selected {
                    Glyph(paths: Icons.chevron, size: 16, lineWidth: 2, color: Palette.secondary)
                }
            }
        }
    }

    private func detailText(_ text: String, selected: Bool) -> some View {
        Text(verbatim: text)
            .font(.app(.golos, 14, weight: selected ? 600 : 400))
            .foregroundStyle(selected ? Palette.text : Palette.secondary)
    }

    private var endRow: some View {
        Menu {
            Button("Never") { setEnd(.never) }
            Button("After 3 times") { setEnd(.count(3)) }
            Button("After 5 times") { setEnd(.count(5)) }
            Button("After 10 times") { setEnd(.count(10)) }
            Button("Until the end of the year") {
                setEnd(.until(LocalDate(year: calendar.component(.year, from: now), month: 12, day: 31)))
            }
        } label: {
            HStack(spacing: 12) {
                Text("Ends")
                    .font(.app(.golos, 16, weight: 500))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: endText)
                    .font(.app(.golos, 14))
                    .foregroundStyle(Palette.secondary)
                Glyph(paths: Icons.chevron, size: 16, lineWidth: 2, color: Palette.secondary)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .foregroundStyle(Palette.text)
        }
        .disabled(schedule.rule == nil)
        .opacity(schedule.rule == nil ? 0.5 : 1)
    }

    private var endText: String {
        switch schedule.end {
        case .never: return String(localized: "Never")
        case .count(let count): return String(localized: "after \(count) times")
        case .until(let date):
            let reference = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 12)) ?? now
            return String(localized: "until \(reference.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)))")
        }
    }

    private func select(_ option: Kind) {
        let start = schedule.start
        let rule: RepeatRule?
        switch option {
        case .once: rule = nil
        case .daily: rule = .daily
        case .weekdays: rule = .weekdays
        case .weekly: rule = .weekly([start.weekday])
        case .everyDays: rule = .everyDays(3)
        case .monthly: rule = .monthlyOnDay(start.day)
        case .yearly: rule = .yearly(month: start.month, day: start.day)
        }
        Feedback.play(.select)
        setRule(rule)
    }

    private func setRule(_ rule: RepeatRule?) {
        withAnimation(Motion.standard) {
            var updated = schedule
            updated.rule = rule
            if rule == nil {
                updated.end = .never
            }
            draft.schedule = updated
        }
    }

    private func setEnd(_ end: RepeatEnd) {
        withAnimation(Motion.standard) {
            var updated = schedule
            updated.end = end
            draft.schedule = updated
        }
        Feedback.play(.select)
    }

    private func shortDate(_ date: Date) -> String {
        let dayMonth = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated))
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
        return "\(dayMonth) \(calendar.component(.year, from: date))"
    }

    private func longDate(month: Int, day: Int) -> String {
        let reference = calendar.date(from: DateComponents(year: 2000, month: month, day: day, hour: 12)) ?? now
        return reference.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.wide))
    }
}
