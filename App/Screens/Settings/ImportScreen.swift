import EventKit
import RemaCore
import SwiftUI

// Moves reminders over from the Reminders app; nothing is deleted there.
struct ImportScreen: View {
    let store: Store
    var now: Date = Date()
    var calendar: Calendar = .current
    let onBack: () -> Void

    struct ReminderList: Identifiable, Equatable {
        let id: String
        let title: String
        var dated: Int
        var undated: Int
    }

    @State private var lists: [ReminderList] = []
    @State private var chosen: Set<String> = []
    @State private var openOnly = true
    @State private var undatedTomorrow = true
    @State private var loading = true
    @State private var loaded = false
    @State private var denied = false
    @State private var moving = false
    @State private var moved: Int?

    private static let source = EKEventStore()
    private var source: EKEventStore { Self.source }

    private var count: Int {
        lists.filter { chosen.contains($0.id) }.reduce(0) { $0 + $1.dated + (undatedTomorrow ? $1.undated : 0) }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(denied ? LocalizedStringKey("Allow access to Reminders in Settings to move them over.") : LocalizedStringKey("Rema will move your reminders over from the Reminders app. Dates and repeats stay, places and attachments do not. Nothing is deleted in Reminders."))
                        .font(.app(.golos, 15))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.top, 14)
                    if let moved {
                        Text(verbatim: String(localized: "Moved \(moved) reminders", bundle: .app, locale: .app))
                            .font(.app(.golos, 17, weight: 600))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    } else if loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    } else if lists.isEmpty, !denied {
                        Text("No reminders to move")
                            .font(.app(.golos, 17, weight: 600))
                            .foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    } else if !lists.isEmpty {
                        SectionLabel(text: "Lists")
                            .padding(.horizontal, 4)
                            .padding(.top, 20)
                            .padding(.bottom, 8)
                        PanelList {
                            ForEach(Array(lists.enumerated()), id: \.element.id) { index, list in
                                listRow(list)
                                if index < lists.count - 1 {
                                    Hairline()
                                }
                            }
                        }
                        SectionLabel(text: "What to take")
                            .padding(.horizontal, 4)
                            .padding(.top, 20)
                            .padding(.bottom, 8)
                        PanelList {
                            ToggleRow(icon: Icons.check, iconColor: Palette.text, title: "Only not done", subtitle: String(localized: "done ones stay there", bundle: .app, locale: .app), isOn: $openOnly, minHeight: 60)
                            Hairline()
                            ToggleRow(icon: Icons.calendar, iconColor: Palette.text, title: "Without a date for tomorrow at 9:00", subtitle: String(localized: "otherwise these are skipped", bundle: .app, locale: .app), isOn: $undatedTomorrow, minHeight: 60)
                        }
                    }
                    if denied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Settings")
                        }
                        .buttonStyle(SmallButtonStyle(prominent: false))
                        .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "From Reminders", leading: .back, action: onBack)
            }
            if moved != nil {
                PrimaryBar(action: onBack) {
                    Text("Done")
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if count > 0 {
                PrimaryBar(action: move) {
                    Text(verbatim: String(localized: "Move \(count)", bundle: .app, locale: .app))
                        .contentTransition(.numericText())
                }
                .disabled(moving)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: count)
        .animation(Motion.standard, value: moved)
        .task(id: openOnly) { await load() }
    }

    private func listRow(_ list: ReminderList) -> some View {
        let on = chosen.contains(list.id)
        return Button {
            Feedback.play(on ? .uncheck : .check)
            if on {
                chosen.remove(list.id)
            } else {
                chosen.insert(list.id)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: list.title)
                        .font(.app(.golos, 16, weight: 500))
                        .lineLimit(1)
                    Text(verbatim: list.dated > 0 ? String(localized: "\(list.dated + list.undated) reminders", bundle: .app, locale: .app) : String(localized: "\(list.undated) without a date", bundle: .app, locale: .app))
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CheckBox(isOn: on)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func load() async {
        let granted = (try? await source.requestFullAccessToReminders()) ?? false
        guard granted else {
            denied = true
            loading = false
            return
        }
        // What is already in Rema under the same name is not moved again, so it is not counted either.
        let existing = Set(store.activeReminders.map(\.title))
        var found: [ReminderList] = []
        for list in source.calendars(for: .reminder) {
            let items = await fetch([list]).filter { item in
                let title = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return !title.isEmpty && !existing.contains(String(title.prefix(Reminder.maximumTitleLength)))
            }
            let dated = items.filter { $0.dueDateComponents != nil }.count
            if !items.isEmpty {
                found.append(ReminderList(id: list.calendarIdentifier, title: list.title, dated: dated, undated: items.count - dated))
            }
        }
        lists = found
        if !loaded {
            chosen = Set(found.map(\.id))
            loaded = true
        }
        loading = false
    }

    private func fetch(_ lists: [EKCalendar]) async -> [EKReminder] {
        let predicate = openOnly ? source.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists) : source.predicateForReminders(in: lists)
        return await withCheckedContinuation { continuation in
            source.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func move() {
        moving = true
        Task {
            let picked = source.calendars(for: .reminder).filter { chosen.contains($0.calendarIdentifier) }
            let items = await fetch(picked)
            var existing = Set(store.activeReminders.map(\.title))
            var added: [Reminder] = []
            var spread = 0
            for item in items {
                guard let reminder = converted(item, spread: &spread), !existing.contains(reminder.title) else { continue }
                existing.insert(reminder.title)
                added.append(reminder)
            }
            store.saveAll(added)
            Feedback.play(.save)
            Notifier.shared.requestPermissionIfNeeded()
            moving = false
            moved = added.count
        }
    }

    private func moment(_ day: LocalDate, _ time: LocalTime) -> Date {
        calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute)) ?? now
    }

    // A date without a time takes the morning; a repeat keeps its kind where Rema has one, an unusual one is dropped rather than guessed.
    private func converted(_ item: EKReminder, spread: inout Int) -> Reminder? {
        let title = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let today = LocalDate(now, in: calendar)
        var schedule: Schedule?
        if let due = item.dueDateComponents, let year = due.year, let month = due.month, let day = due.day {
            let time = LocalTime(hour: due.hour ?? store.settings.morning.hour, minute: due.hour == nil ? store.settings.morning.minute : due.minute ?? 0)
            var start = LocalDate(year: year, month: month, day: day)
            // An overdue single reminder would never ring, it moves to the same time ahead.
            if item.recurrenceRules?.isEmpty ?? true, !item.isCompleted, moment(start, time) <= now {
                start = moment(today, time) > now ? today : today.adding(days: 1)
            }
            schedule = Schedule(start: start, time: time)
        } else if undatedTomorrow {
            // Undated ones go tomorrow ten minutes apart from the morning, not all into one minute.
            let first = store.settings.morning.hour * 60 + store.settings.morning.minute
            let minutes = min(first + 10 * spread, 22 * 60)
            spread += 1
            schedule = Schedule(start: today.adding(days: 1), time: LocalTime(hour: minutes / 60, minute: minutes % 60))
        } else {
            return nil
        }
        if var plan = schedule, let rule = item.recurrenceRules?.first {
            let interval = max(rule.interval, 1)
            let days = (rule.daysOfTheWeek ?? []).compactMap { Weekday(rawValue: ($0.dayOfTheWeek.rawValue + 5) % 7 + 1) }
            switch rule.frequency {
            case .daily:
                plan.rule = interval == 1 ? .daily : .everyDays(interval)
            case .weekly where interval == 1:
                plan.rule = .weekly(days.isEmpty ? [plan.start.weekday] : days)
            case .weekly where days.count <= 1:
                while let day = days.first, plan.start.weekday != day {
                    plan.start = plan.start.adding(days: 1)
                }
                plan.rule = .everyDays(7 * interval)
            case .monthly:
                if let day = rule.daysOfTheWeek?.first, let weekday = days.first {
                    let ordinal = day.weekNumber != 0 ? day.weekNumber : rule.setPositions?.first?.intValue ?? 1
                    plan.rule = interval == 1 ? .monthlyOnWeekday(ordinal: ordinal, weekday: weekday) : nil
                } else {
                    plan.rule = interval == 1 ? .monthlyOnDay(plan.start.day) : .everyMonths(interval)
                }
            case .yearly where interval == 1:
                plan.rule = .yearly(month: plan.start.month, day: plan.start.day)
            default:
                break
            }
            if plan.rule != nil, let end = rule.recurrenceEnd {
                if let date = end.endDate {
                    plan.end = .until(LocalDate(date, in: calendar))
                } else if end.occurrenceCount > 0 {
                    plan.end = .count(end.occurrenceCount)
                }
            }
            schedule = plan
        }
        var reminder = Reminder(title: String(title.prefix(Reminder.maximumTitleLength)), schedule: schedule, urgent: (1...4).contains(item.priority), createdAt: Date())
        // A done one comes over done, without a tick in the history.
        if item.isCompleted, let plan = schedule {
            reminder.completedThrough = max(moment(plan.start, plan.time), item.completionDate ?? .distantPast)
        }
        return reminder
    }
}
