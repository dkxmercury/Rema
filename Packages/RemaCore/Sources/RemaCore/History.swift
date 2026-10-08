import Foundation

public struct HistoryEntry: Equatable, Sendable {
    public let reminderID: UUID
    public let title: String
    public let occurrence: Date
    public let at: Date
}

public struct Streak: Equatable, Sendable {
    public let reminderID: UUID
    public let title: String
    public let count: Int
    public let daily: Bool
    public let recent: [Bool]
    // Every time in the window was done and the repeat ran before it, so the streak is longer than the count.
    public let longer: Bool
}

public enum History {
    // Ticks of the last days, newest first.
    public static func entries(_ reminders: [Reminder], since start: Date) -> [HistoryEntry] {
        reminders
            .filter(\.isLive)
            .flatMap { reminder in
                reminder.history.filter { $0.at >= start }.map { HistoryEntry(reminderID: reminder.id, title: reminder.title, occurrence: $0.occurrence, at: $0.at) }
            }
            .sorted { $0.at > $1.at }
    }

    // Repeats done so many times in a row, the longest first. Today's time that has not been ticked yet does not break a streak.
    public static func streaks(_ reminders: [Reminder], now: Date, calendar: Calendar, minimum: Int = 3) -> [Streak] {
        reminders.compactMap { reminder -> Streak? in
            guard reminder.deletedAt == nil, let schedule = reminder.schedule, let rule = schedule.rule, !reminder.history.isEmpty else { return nil }
            let window = now.addingTimeInterval(-90 * 86_400)
            let times = Recurrence.next(schedule, after: window, limit: 500, calendar: calendar).filter { $0 <= now }
            guard !times.isEmpty else { return nil }
            let marks = reminder.history.map(\.occurrence)
            // A tick counts for its occurrence even when a snooze moved it, so anything up to the next occurrence belongs to it.
            var done = times.indices.map { index in
                let end = index + 1 < times.count ? times[index + 1] : .distantFuture
                return marks.contains { $0 >= times[index] && $0 < end }
            }
            if let last = times.last, !done[done.count - 1], calendar.isDate(last, inSameDayAs: now) {
                done.removeLast()
            }
            let count = done.reversed().prefix { $0 }.count
            guard count >= minimum else { return nil }
            let earlier = Recurrence.next(schedule, after: window.addingTimeInterval(-400 * 86_400), limit: 1, calendar: calendar).first
            let longer = count == done.count && earlier.map { $0 < times[0] } == true
            return Streak(reminderID: reminder.id, title: reminder.title, count: count, daily: isDaily(rule), recent: Array(done.reversed().prefix(7)), longer: longer)
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.title < $1.title }
    }

    private static func isDaily(_ rule: RepeatRule) -> Bool {
        switch rule {
        case .daily:
            return true
        case .everyDays(let count):
            return count == 1
        case .weekly(let days):
            return Set(days).count == 7
        default:
            return false
        }
    }
}
