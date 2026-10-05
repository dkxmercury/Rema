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
            for occurrence in Recurrence.next(schedule, after: start.addingTimeInterval(-1), limit: 3, calendar: calendar) where occurrence < end {
                items.append(AgendaItem(reminderID: reminder.id, occurrence: occurrence, done: isDone(reminder, occurrence)))
            }
        }
        return items.sorted { $0.occurrence == $1.occurrence ? $0.reminderID.uuidString < $1.reminderID.uuidString : $0.occurrence < $1.occurrence }
    }

    public static func upcoming(after now: Date, reminders: [Reminder], calendar: Calendar, limit: Int = 20) -> [AgendaItem] {
        var items: [AgendaItem] = []
        for reminder in reminders where reminder.deletedAt == nil {
            guard let schedule = reminder.schedule else { continue }
            let from = max(now, reminder.completedThrough ?? now)
            if let next = Recurrence.next(schedule, after: from, limit: 1, calendar: calendar).first {
                items.append(AgendaItem(reminderID: reminder.id, occurrence: next, done: false))
            }
        }
        return Array(items.sorted { $0.occurrence < $1.occurrence }.prefix(limit))
    }

    public static func isDone(_ reminder: Reminder, _ occurrence: Date) -> Bool {
        guard let done = reminder.completedThrough else { return false }
        return occurrence <= done
    }
}
