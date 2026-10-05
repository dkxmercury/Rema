import AppIntents
import RemaCore
import SwiftUI

struct AddReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Create reminder"
    static let description = IntentDescription("Adds a reminder from a phrase, for example tomorrow at 9 call mom.")

    @Parameter(title: "What and when", requestValueDialog: IntentDialog("What and when to remind?"))
    var phrase: String

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = Store.shared
        let now = Date()
        let parsed = PhraseParser(now: now, calendar: .current, morning: store.settings.morning, evening: store.settings.evening, places: store.activePlaces.map(\.name), preferred: Bundle.main.preferredLocalizations.first).parse(phrase)
        guard !parsed.title.isEmpty else {
            throw $phrase.needsValueError(IntentDialog("What should I remind about?"))
        }
        let placeIDs = parsed.placeNames.compactMap { name in store.activePlaces.first { $0.name == name }?.id }
        let schedule = parsed.schedule ?? (placeIDs.isEmpty ? IntentSupport.soon(after: now) : nil)
        let reminder = Reminder(
            title: parsed.title,
            schedule: schedule,
            preAlerts: parsed.preAlerts,
            nag: parsed.nag,
            urgent: parsed.urgent,
            placeIDs: placeIDs,
            placeTrigger: parsed.placeTrigger ?? .arrive,
            createdAt: now
        )
        store.save(reminder)
        Notifier.shared.requestPermissionIfNeeded()
        Feedback.play(.save)
        let when = IntentSupport.when(reminder, store: store, now: now)
        return .result(dialog: IntentDialog("Done, I'll remind you."), view: ReminderSnippet(title: reminder.title, when: when))
    }
}

struct NextReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Next reminder"
    static let description = IntentDescription("Tells what is next and how soon.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = Store.shared
        let now = Date()
        guard let next = Agenda.upcoming(after: now, reminders: store.activeReminders, calendar: .current, limit: 1).first,
              let reminder = store.reminder(next.reminderID) else {
            return .result(dialog: IntentDialog("Nothing ahead."), view: ReminderSnippet(title: String(localized: "Nothing ahead"), when: ""))
        }
        let describer = Describer()
        let when = "\(describer.dayAndTime(next.occurrence, now: now).capitalizedFirst(.current)), \(describer.countdown(from: now, to: next.occurrence))"
        return .result(dialog: IntentDialog(stringLiteral: "\(reminder.title). \(when)."), view: ReminderSnippet(title: reminder.title, when: when))
    }
}

struct CompleteReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark as done"
    static let description = IntentDescription("Marks the current or the next reminder as done.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        guard let target = IntentSupport.current(store: store, now: Date()), let reminder = store.reminder(target.reminderID) else {
            return .result(dialog: IntentDialog("Nothing to mark."))
        }
        store.complete(target.reminderID, through: target.occurrence)
        await ReminderNotifications.clear(target.reminderID, occurrence: target.occurrence)
        await ReminderNotifications.endActivities(for: target.reminderID)
        Notifier.shared.scheduleSoon()
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Done: \(reminder.title)")))
    }
}

struct SnoozeReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Snooze reminder"
    static let description = IntentDescription("Moves the current or the next reminder a bit later.")

    @Parameter(title: "Minutes", default: 10, inclusiveRange: (1, 240))
    var minutes: Int

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        let now = Date()
        guard let target = IntentSupport.current(store: store, now: now), let reminder = store.reminder(target.reminderID) else {
            return .result(dialog: IntentDialog("Nothing to snooze."))
        }
        store.snooze(target.reminderID, until: now.addingTimeInterval(Double(minutes) * 60))
        await ReminderNotifications.clear(target.reminderID, occurrence: target.occurrence)
        await ReminderNotifications.endActivities(for: target.reminderID)
        Notifier.shared.scheduleSoon()
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Snoozed by \(minutes) min: \(reminder.title)")))
    }
}

struct RemaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddReminderIntent(),
            phrases: ["Remind me in \(.applicationName)", "New reminder in \(.applicationName)"],
            shortTitle: "Create reminder",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: NextReminderIntent(),
            phrases: ["What is next in \(.applicationName)", "Next reminder in \(.applicationName)"],
            shortTitle: "Next reminder",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: CompleteReminderIntent(),
            phrases: ["Mark done in \(.applicationName)"],
            shortTitle: "Mark as done",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: SnoozeReminderIntent(),
            phrases: ["Snooze in \(.applicationName)"],
            shortTitle: "Snooze reminder",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}

enum IntentSupport {
    static func soon(after now: Date) -> Schedule {
        let calendar = Calendar.current
        let later = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        let minute = calendar.component(.minute, from: later)
        let rounded = calendar.date(byAdding: .minute, value: (5 - minute % 5) % 5, to: later) ?? later
        let parts = calendar.dateComponents([.hour, .minute], from: rounded)
        return Schedule(start: LocalDate(rounded, in: calendar), time: LocalTime(hour: parts.hour ?? 9, minute: parts.minute ?? 0))
    }

    static func when(_ reminder: Reminder, store: Store, now: Date) -> String {
        let describer = Describer()
        if let schedule = reminder.schedule, let date = Recurrence.next(schedule, after: now.addingTimeInterval(-60), limit: 1, calendar: .current).first {
            return describer.dayAndTime(date, now: now).capitalizedFirst(.current)
        }
        return describer.placeText(reminder, places: store.places).capitalizedFirst(.current)
    }

    static func current(store: Store, now: Date) -> AgendaItem? {
        let today = Agenda.day(now, reminders: store.activeReminders, calendar: .current)
        if let overdue = today.last(where: { !$0.done && $0.occurrence <= now }) {
            return overdue
        }
        return Agenda.upcoming(after: now, reminders: store.activeReminders, calendar: .current, limit: 1).first
    }
}

struct ReminderSnippet: View {
    let title: String
    let when: String

    var body: some View {
        HStack(spacing: 12) {
            MiniDial(hour: Calendar.current.component(.hour, from: Date()), minute: Calendar.current.component(.minute, from: Date()), size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.app(.golos, 16, weight: 600))
                if !when.isEmpty {
                    Text(verbatim: when)
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.text)
        .padding(14)
    }
}
