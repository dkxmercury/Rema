import Foundation

public struct AgendaItem: Equatable, Sendable {
    public let reminderID: UUID
    public let occurrence: Date
    public let done: Bool
}

public enum Agenda {
    public static func day(_ date: Date, reminders: [Reminder], calendar: Calendar) -> [AgendaItem] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        var items: [AgendaItem] = []
        for reminder in reminders where reminder.deletedAt == nil {
            guard let schedule = reminder.schedule else { continue }
            for occurrence in Recurrence.next(schedule, after: start.addingTimeInterval(-1), limit: 48, calendar: calendar) where occurrence < end {
                items.append(AgendaItem(reminderID: reminder.id, occurrence: occurrence, done: isDone(reminder, occurrence)))
            }
        }
        return items.sorted { $0.occurrence == $1.occurrence ? $0.reminderID.uuidString < $1.reminderID.uuidString : $0.occurrence < $1.occurrence }
    }

    // The occurrence a list belongs to: today's one not done yet, otherwise the next one.
    public static func current(_ reminder: Reminder, now: Date, calendar: Calendar) -> Date? {
        guard let schedule = reminder.schedule else { return nil }
        if let today = day(now, reminders: [reminder], calendar: calendar).first(where: { !$0.done }) {
            return today.occurrence
        }
        return Recurrence.next(schedule, after: max(now, reminder.completedThrough ?? now), limit: 1, calendar: calendar).first
    }

    // The time a list is ticked for. Today's one counts even when done, so a finished list opens finished and not as the next time.
    public static func listOccurrence(_ reminder: Reminder, now: Date, calendar: Calendar) -> Date {
        let today = day(now, reminders: [reminder], calendar: calendar)
        if let pending = today.first(where: { !$0.done }) {
            return pending.occurrence
        }
        if let finished = today.last {
            return finished.occurrence
        }
        return current(reminder, now: now, calendar: calendar) ?? reminder.completedThrough ?? now
    }

    public static func upcoming(after now: Date, reminders: [Reminder], calendar: Calendar, limit: Int = 20) -> [AgendaItem] {
        var items: [AgendaItem] = []
        for reminder in reminders where reminder.deletedAt == nil {
            guard let schedule = reminder.schedule else { continue }
            let from = max(now, reminder.completedThrough ?? now)
            var next = Recurrence.next(schedule, after: from, limit: 1, calendar: calendar).first
            // A snooze rings on its own and is usually sooner than the next regular time.
            if let snoozed = reminder.snoozedUntil, snoozed > now, next.map({ snoozed < $0 }) ?? true {
                next = snoozed
            }
            if let next {
                items.append(AgendaItem(reminderID: reminder.id, occurrence: next, done: false))
            }
        }
        return Array(items.sorted { $0.occurrence < $1.occurrence }.prefix(limit))
    }

    // Came and went without a tick; a snooze into the future means the person already answered it.
    public static func missed(_ now: Date, reminders: [Reminder], calendar: Calendar, grace: TimeInterval = 60) -> [AgendaItem] {
        let byID = Dictionary(reminders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return day(now, reminders: reminders, calendar: calendar).filter { item in
            guard !item.done, item.occurrence.addingTimeInterval(grace) < now, let reminder = byID[item.reminderID] else { return false }
            return !(reminder.snoozedUntil.map { $0 > now } ?? false)
        }
    }

    public static func isDone(_ reminder: Reminder, _ occurrence: Date) -> Bool {
        guard let done = reminder.completedThrough else { return false }
        return occurrence <= done
    }
}
