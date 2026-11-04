import Foundation

public struct PillForecast: Equatable, Sendable {
    public let pills: Int
    // Days the pills last, counting the day asked about; nil when no dose is coming.
    public let days: Int?
    public let lastDose: Date?
    public let low: Bool
}

public enum PillCount {
    static let lookAhead = 1_100

    public static func left(_ course: PillCourse, reminders: [Reminder]) -> Int {
        let ticks = reminders
            .filter { course.reminderIDs.contains($0.id) }
            .reduce(0) { sum, reminder in sum + reminder.history.filter { $0.at > course.counted }.count }
        return max(0, course.left - ticks * max(course.perDose, 1))
    }

    // Doses still to take from the start of today, without the ticked and skipped ones.
    static func doses(_ course: PillCourse, reminders: [Reminder], now: Date, limit: Int, calendar: Calendar) -> [Date] {
        let start = calendar.startOfDay(for: now).addingTimeInterval(-1)
        var dates: [Date] = []
        for reminder in reminders where course.reminderIDs.contains(reminder.id) && reminder.isLive {
            guard let schedule = reminder.schedule else { continue }
            dates += Recurrence.next(schedule, after: start, limit: limit, calendar: calendar).filter { !reminder.isDone($0) }
        }
        return dates.sorted()
    }

    // At a later moment the doses due before it count as taken; at the present the box is as it is.
    public static func forecast(_ course: PillCourse, reminders: [Reminder], at moment: Date? = nil, now: Date, calendar: Calendar) -> PillForecast {
        let dose = max(course.perDose, 1)
        let moment = max(moment ?? now, now)
        let box = left(course, reminders: reminders)
        // A reminder comes at most once a day, so this many dates per reminder always reach past the last pill.
        let span = Int((moment.timeIntervalSince(now) / 86_400).rounded(.up)) + 1
        let pending = doses(course, reminders: reminders, now: now, limit: min(lookAhead, box / dose + 2 + span), calendar: calendar)
        let taken = pending.filter { $0 >= now && $0 < moment }.count
        let pills = max(0, box - taken * dose)
        let ahead = moment > now ? pending.filter { $0 >= moment } : pending
        guard !ahead.isEmpty else {
            return PillForecast(pills: pills, days: nil, lastDose: nil, low: false)
        }
        let covered = min(ahead.count, pills / dose)
        let last = covered > 0 ? ahead[covered - 1] : nil
        let days = last.map { (calendar.dateComponents([.day], from: calendar.startOfDay(for: moment), to: calendar.startOfDay(for: $0)).day ?? 0) + 1 } ?? 0
        // Pills that last to the end of the course are enough, however few days are left.
        let low = covered < ahead.count && days <= course.warnDays
        return PillForecast(pills: pills, days: days, lastDose: last, low: low)
    }

    // The reminders one phrase made: the same title, repeating, not yet counted in another course.
    public static func siblings(of reminder: Reminder, in reminders: [Reminder], courses: [PillCourse]) -> [UUID] {
        let title = normalized(reminder.title)
        let taken = Set(courses.filter { !$0.reminderIDs.contains(reminder.id) }.flatMap(\.reminderIDs))
        let others = reminders.filter { other in
            other.id != reminder.id && other.isLive && other.schedule?.rule != nil && !taken.contains(other.id) && normalized(other.title) == title
        }
        let ordered = others.sorted { lhs, rhs in
            let left = lhs.schedule.map { $0.time.hour * 60 + $0.time.minute } ?? 0
            let right = rhs.schedule.map { $0.time.hour * 60 + $0.time.minute } ?? 0
            return left < right
        }
        return [reminder.id] + ordered.map(\.id)
    }

    static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
