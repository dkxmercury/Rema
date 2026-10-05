import RemaCore
import SwiftUI

struct CalendarScreen: View {
    enum Mode: Hashable {
        case week
        case month
    }

    let store: Store
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let onClose: () -> Void

    @State private var mode: Mode = .month
    @State private var selected: LocalDate
    @State private var page: LocalDate
    @State private var forward = true
    @State private var rowTransition: AnyTransition = .opacity
    @State private var editing: EditingTarget?
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: Store, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current, onClose: @escaping () -> Void) {
        self.store = store
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.onClose = onClose
        let today = LocalDate(now, in: calendar)
        _selected = State(initialValue: today)
        _page = State(initialValue: LocalDate(year: today.year, month: today.month, day: 1))
    }

    private var today: LocalDate {
        LocalDate(now, in: calendar)
    }

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Segmented(options: [(Mode.week, "Week"), (Mode.month, "Month")], selection: modeBinding)
                        .padding(.top, 14)
                    grid
                        .padding(.top, 12)
                    SectionLabel(verbatim: describer.dayTitle(date(selected)))
                        .contentTransition(.opacity)
                        .padding(.top, 16)
                    dayList
                        .padding(.top, 8)
                }
                .padding(.horizontal, 18)
                .padding(.top, 15)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: selected)
        .animation(Motion.standard, value: store.reminders)
        .fullScreenCover(item: $editing) { target in
            EditorScreen(draft: target.reminder, isNew: target.isNew, store: store, onClose: { editing = nil })
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: showToday) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: monthTitle)
                        .font(.app(.jost, 32, weight: 500))
                        .contentTransition(.numericText(countsDown: !forward))
                    Text(verbatim: String(shownMonth.year))
                        .font(.app(.jost, 20))
                        .foregroundStyle(Palette.secondary)
                        .contentTransition(.numericText(countsDown: !forward))
                }
                .lineBox(36, .jost, 32, weight: 500)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Show today"))
            Spacer(minLength: 8)
            RoundIconButton(icon: Icons.back, label: mode == .month ? "Previous month" : "Previous week") { move(-1) }
            RoundIconButton(icon: Icons.chevron, label: mode == .month ? "Next month" : "Next week") { move(1) }
        }
        .contentShape(Rectangle())
        .gesture(closeDrag)
    }

    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                if value.translation.height > 100, abs(value.translation.width) < value.translation.height {
                    onClose()
                }
            }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(verbatim: symbol)
                        .font(.app(.golos, 11, weight: 600))
                        .tracking(0.66)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 20)
            VStack(spacing: 0) {
                ForEach(visibleWeeks, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(week, id: \.self) { day in
                            dayCell(day)
                        }
                    }
                    .transition(rowTransition)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .circular))
        .panel()
        .simultaneousGesture(pageSwipe)
    }

    private var pageSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 40, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                move(dx < 0 ? 1 : -1)
            }
    }

    @ViewBuilder
    private func dayCell(_ day: LocalDate) -> some View {
        let inMonth = mode == .week || day.month == shownMonth.month
        let isToday = day == today
        let items = Agenda.day(date(day), reminders: store.reminders, calendar: calendar)
        let content = VStack(spacing: 3) {
            ZStack {
                if isToday {
                    Circle()
                        .fill(Palette.accent)
                        .insetShadow(Circle(), .black.opacity(0.14), y: -2)
                } else if day == selected, inMonth {
                    Circle()
                        .strokeBorder(Palette.text, lineWidth: 1.5)
                        .matchedGeometryEffect(id: "selected", in: selection)
                }
                Text(verbatim: "\(day.day)")
                    .font(.app(.golos, 16, weight: isToday ? 600 : 400))
                    .foregroundStyle(isToday ? Palette.onAccent : (inMonth ? Palette.text : Palette.otherMonth))
            }
            .frame(width: 34, height: 34)
            HStack(spacing: 3) {
                if inMonth {
                    ForEach(Array(dots(items).enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        if inMonth {
            Button {
                selected = day
                Feedback.play(.select)
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(Text(verbatim: dayAccessibility(day, count: items.count, isToday: isToday)))
            .accessibilityAddTraits(day == selected ? .isSelected : [])
        } else {
            content
                .accessibilityHidden(true)
        }
    }

    private func dots(_ items: [AgendaItem]) -> [Color] {
        let kinds = items.compactMap { item -> Int? in
            guard let reminder = store.reminder(item.reminderID) else { return nil }
            if case .yearly = reminder.schedule?.rule { return 0 }
            return reminder.urgent ? 1 : 2
        }
        return kinds.sorted().prefix(3).map { kind in
            switch kind {
            case 0: return Palette.yearly
            case 1: return Palette.urgent
            default: return Palette.text
            }
        }
    }

    private func dayAccessibility(_ day: LocalDate, count: Int, isToday: Bool) -> String {
        let name = date(day).formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.wide))
        let parts = [name, isToday ? String(localized: "today") : nil, String(localized: "\(count) reminders")]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }

    private var dayRows: [HomeContent.Row] {
        HomeContent.rows(on: date(selected), reminders: store.reminders, places: store.places, now: now, calendar: calendar, locale: locale)
    }

    @ViewBuilder
    private var dayList: some View {
        let rows = dayRows
        if rows.isEmpty {
            Text("Nothing planned")
                .font(.app(.golos, 15))
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .panel()
                .transition(.opacity)
        } else {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    AgendaRow(row: row, minHeight: 50, onToggle: { toggle(row) })
                        .contentShape(Rectangle())
                        .onTapGesture { open(row.reminderID) }
                        .transition(.opacity)
                    if row.id != rows.last?.id {
                        Hairline()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
            .panel()
            .transition(.opacity)
        }
    }

    private var modeBinding: Binding<Mode> {
        Binding(
            get: { mode },
            set: { newMode in
                guard newMode != mode else { return }
                rowTransition = .opacity
                DispatchQueue.main.async {
                    withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) {
                        mode = newMode
                        page = LocalDate(year: selected.year, month: selected.month, day: 1)
                    }
                }
            }
        )
    }

    private func move(_ step: Int) {
        forward = step > 0
        rowTransition = reduceMotion ? .opacity : .push(from: forward ? .trailing : .leading)
        Feedback.play(.select)
        DispatchQueue.main.async {
            withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) {
                if mode == .month {
                    page = page.addingMonths(step)
                    selected = page.year == today.year && page.month == today.month ? today : page
                } else {
                    selected = selected.adding(days: 7 * step)
                    page = LocalDate(year: selected.year, month: selected.month, day: 1)
                }
            }
        }
    }

    private func showToday() {
        guard selected != today || page.month != today.month || page.year != today.year else { return }
        forward = today > selected
        rowTransition = reduceMotion ? .opacity : .push(from: forward ? .trailing : .leading)
        DispatchQueue.main.async {
            withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) {
                selected = today
                page = LocalDate(year: today.year, month: today.month, day: 1)
            }
        }
    }

    private func toggle(_ row: HomeContent.Row) {
        Feedback.play(row.done ? .uncheck : .check)
        withAnimation(Motion.standard) {
            if row.done {
                store.reopen(row.reminderID, before: row.occurrence)
            } else {
                store.complete(row.reminderID, through: row.occurrence)
            }
        }
    }

    private func open(_ id: UUID) {
        guard let reminder = store.reminder(id) else { return }
        editing = EditingTarget(reminder: reminder, isNew: false)
    }

    private var shownMonth: LocalDate {
        mode == .month ? page : LocalDate(year: selected.year, month: selected.month, day: 1)
    }

    private var monthTitle: String {
        date(shownMonth).formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.wide)).capitalizedFirst(locale)
    }

    private var weekdaySymbols: [String] {
        var formatter = calendar
        formatter.locale = locale
        let symbols = formatter.shortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private var visibleWeeks: [[LocalDate]] {
        let weeks = monthWeeks(shownMonth)
        guard mode == .week else { return weeks }
        return weeks.filter { $0.contains(selected) }
    }

    private func monthWeeks(_ month: LocalDate) -> [[LocalDate]] {
        let first = LocalDate(year: month.year, month: month.month, day: 1)
        let count = LocalDate.days(in: month.month, year: month.year)
        let last = LocalDate(year: month.year, month: month.month, day: count)
        var start = first.adding(days: -column(first))
        var weeks: [[LocalDate]] = []
        while start <= last {
            weeks.append((0..<7).map { start.adding(days: $0) })
            start = start.adding(days: 7)
        }
        return weeks
    }

    private func column(_ day: LocalDate) -> Int {
        let foundationWeekday = day.weekday.rawValue % 7 + 1
        return (foundationWeekday - calendar.firstWeekday + 7) % 7
    }

    private func date(_ day: LocalDate) -> Date {
        calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? now
    }
}

private extension LocalDate {
    func addingMonths(_ count: Int) -> LocalDate {
        let index = year * 12 + (month - 1) + count
        return LocalDate(year: index / 12, month: index % 12 + 1, day: 1)
    }
}
