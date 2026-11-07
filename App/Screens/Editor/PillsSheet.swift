import RemaCore
import SwiftUI

struct PillCounter: View {
    @Binding var count: Int
    let label: LocalizedStringKey
    @State private var text = ""

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 24) {
                step(-1, icon: Icons.minus, label: "One fewer")
                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.app(.jost, 64, weight: 500))
                    .monospacedDigit()
                    .frame(width: 128)
                    .accessibilityLabel(Text(label))
                step(1, icon: Icons.plus, label: "One more")
            }
            Text(label)
                .font(.app(.golos, 14))
                .foregroundStyle(Palette.secondary)
        }
        .padding(.top, 18)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .panel()
        .onAppear { text = String(count) }
        .onChange(of: count) { _, value in
            if text != String(value) {
                text = String(value)
            }
        }
        .onChange(of: text) { _, value in
            // Digits of any script count, so an Arabic keyboard types the same number.
            let digits = value.compactMap(\.wholeNumberValue).prefix(3)
            let number = min(digits.reduce(0) { $0 * 10 + $1 }, PillCourse.maximumPills)
            if number != count {
                count = number
            }
            if !value.isEmpty, value != String(number) {
                text = String(number)
            }
        }
    }

    private func step(_ delta: Int, icon: [String], label: LocalizedStringKey) -> some View {
        Button {
            count = min(max(count + delta, 0), PillCourse.maximumPills)
            Feedback.play(.select)
        } label: {
            ZStack {
                RaisedCircle(size: 52)
                Glyph(paths: icon, size: 22, lineWidth: 2.4, color: Palette.text)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(label))
    }
}

struct PillsSheet: View {
    let reminder: Reminder
    let initial: PillCourse?
    let store: Store
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let onDone: (PillCourse?) -> Void
    private let ids: [UUID]
    private let courseID: UUID
    @State private var count: Int
    @State private var perDose: Int
    @State private var warnDays: Int

    init(reminder: Reminder, course: PillCourse?, store: Store, now: Date = Date(), calendar: Calendar = .current, locale: Locale = AppLanguage.current.locale, onDone: @escaping (PillCourse?) -> Void) {
        self.reminder = reminder
        self.initial = course
        self.store = store
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.onDone = onDone
        let reminders = Self.reminders(store: store, draft: reminder)
        ids = course?.reminderIDs ?? PillCount.siblings(of: reminder, in: reminders, courses: store.settings.courses ?? [])
        courseID = course?.id ?? UUID()
        _count = State(initialValue: course.map { PillCount.left($0, reminders: reminders) } ?? 20)
        _perDose = State(initialValue: course?.perDose ?? 1)
        _warnDays = State(initialValue: course?.warnDays ?? 3)
    }

    // The reminder as it stands in the editor, so a new one is counted before it is saved.
    static func reminders(store: Store, draft: Reminder) -> [Reminder] {
        store.reminders.filter { $0.id != draft.id } + [draft]
    }

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    private func course(counted: Date) -> PillCourse {
        PillCourse(id: courseID, reminderIDs: ids, left: count, counted: counted, perDose: perDose, pack: initial?.pack ?? count, warnDays: warnDays)
    }

    private var subtitle: String {
        let reminders = Self.reminders(store: store, draft: reminder)
        let times = ids.compactMap { id in reminders.first { $0.id == id }?.schedule?.time }
            .compactMap { calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: now) }
            .sorted()
        guard !times.isEmpty else { return reminder.title }
        return "\(reminder.title), \(describer.doseTimes(times))"
    }

    private var summary: String {
        let forecast = PillCount.forecast(course(counted: now), reminders: Self.reminders(store: store, draft: reminder), now: now, calendar: calendar)
        let hint = String(localized: "Each Done takes a dose out of the box", bundle: .app, locale: .app)
        return [describer.pillsLasting(forecast), hint].compactMap { $0 }.joined(separator: ". ")
    }

    private func warning(_ days: Int) -> LocalizedStringKey {
        days == 7 ? "a week before" : "\(days) days before"
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pills")
                            .font(.app(.jost, 26, weight: 500))
                        Text(verbatim: subtitle)
                            .font(.app(.golos, 14))
                            .foregroundStyle(Palette.secondary)
                    }
                    .padding(.top, 28)
                    PillCounter(count: $count, label: "left in the box")
                        .padding(.top, 18)
                    SectionLabel(text: "Per dose")
                        .padding(.top, 18)
                        .padding(.horizontal, 4)
                    Segmented(options: PillCourse.doses.map { ($0, LocalizedStringKey(String($0))) }, selection: $perDose)
                        .padding(.top, 8)
                    SectionLabel(text: "Remind to buy")
                        .padding(.top, 18)
                        .padding(.horizontal, 4)
                    Segmented(options: PillCourse.warnings.map { ($0, warning($0)) }, selection: $warnDays, fontSize: 14)
                        .padding(.top, 8)
                    Text(verbatim: summary)
                        .font(.app(.golos, 13))
                        .lineHeight(18, .golos, 13)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                    if initial != nil {
                        Button {
                            Feedback.play(.toggle)
                            onDone(nil)
                        } label: {
                            Text("Don't count pills")
                                .font(.app(.golos, 15, weight: 600))
                                .foregroundStyle(Palette.secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(PressableStyle())
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            PrimaryBar(action: done) {
                Text("Done")
            }
        }
        .foregroundStyle(Palette.text)
    }

    private func done() {
        Feedback.play(.save)
        onDone(course(counted: Date()))
    }
}

struct BoughtSheet: View {
    let course: PillCourse
    let store: Store
    var now: Date = Date()
    var calendar: Calendar = .current
    var locale: Locale = AppLanguage.current.locale
    let onDone: (PillCourse?) -> Void
    @State private var count: Int

    init(course: PillCourse, store: Store, now: Date = Date(), calendar: Calendar = .current, locale: Locale = AppLanguage.current.locale, onDone: @escaping (PillCourse?) -> Void) {
        self.course = course
        self.store = store
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.onDone = onDone
        _count = State(initialValue: course.pack)
    }

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    private var left: Int {
        PillCount.left(course, reminders: store.reminders)
    }

    private var title: String {
        store.activeReminders.first { course.reminderIDs.contains($0.id) }?.title ?? ""
    }

    private func added(counted: Date) -> PillCourse {
        var next = course
        next.left = min(left + count, PillCourse.maximumPills)
        next.counted = counted
        next.pack = max(count, 1)
        return next
    }

    private var summary: String {
        let next = added(counted: now)
        let total = String(localized: "It will be \(next.left)", bundle: .app, locale: .app)
        let forecast = PillCount.forecast(next, reminders: store.reminders, now: now, calendar: calendar)
        return [total, describer.pillsLasting(forecast)].compactMap { $0 }.joined(separator: ". ")
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bought a box")
                        .font(.app(.jost, 26, weight: 500))
                    Text(verbatim: [title, describer.pillsLeft(left)].filter { !$0.isEmpty }.joined(separator: ", "))
                        .font(.app(.golos, 14))
                        .foregroundStyle(Palette.secondary)
                }
                .padding(.top, 28)
                PillCounter(count: $count, label: "in the new box")
                    .padding(.top, 18)
                Text(verbatim: summary)
                    .font(.app(.golos, 13))
                    .lineHeight(18, .golos, 13)
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            PrimaryBar(action: add) {
                Text("Add to the box")
            }
        }
        .foregroundStyle(Palette.text)
    }

    private func add() {
        onDone(count > 0 ? added(counted: Date()) : nil)
    }
}
