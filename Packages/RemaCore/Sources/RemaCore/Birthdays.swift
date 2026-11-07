import Foundation

// A yearly reminder seen as a birthday: whose, when it comes next and how old the person turns then.
public struct BirthdayEntry: Identifiable, Equatable, Sendable {
    public let reminderID: UUID
    public let name: String
    public let month: Int
    public let day: Int
    public let next: LocalDate
    public let daysLeft: Int
    public let turning: Int?

    public var id: UUID { reminderID }
}

public enum Birthdays {
    public static let soon = 30

    // Birthdays added from contacts before they had their own note have only a title, so «Birthday of %@» in each language tells the name.
    public static func entries(_ reminders: [Reminder], today: LocalDate, patterns: [String]) -> [BirthdayEntry] {
        reminders.compactMap { reminder -> BirthdayEntry? in
            guard reminder.isLive, case .yearly(let month, let day) = reminder.schedule?.rule,
                  let name = reminder.birthday?.name ?? legacyName(reminder.title, patterns: patterns) else { return nil }
            let next = coming(month: month, day: day, from: today)
            return BirthdayEntry(reminderID: reminder.id, name: name, month: month, day: day, next: next, daysLeft: next.dayNumber - today.dayNumber, turning: reminder.birthday?.age(on: next))
        }
        .sorted { $0.daysLeft == $1.daysLeft ? $0.name < $1.name : $0.daysLeft < $1.daysLeft }
    }

    // 29 February comes on the 28th in a common year.
    public static func coming(month: Int, day: Int, from today: LocalDate) -> LocalDate {
        func on(_ year: Int) -> LocalDate {
            LocalDate(year: year, month: month, day: min(day, LocalDate.days(in: month, year: year)))
        }
        let thisYear = on(today.year)
        return thisYear >= today ? thisYear : on(today.year + 1)
    }

    static func legacyName(_ title: String, patterns: [String]) -> String? {
        for pattern in patterns {
            let parts = pattern.components(separatedBy: "%@")
            guard parts.count == 2, title.count > parts[0].count + parts[1].count, title.hasPrefix(parts[0]), title.hasSuffix(parts[1]) else { continue }
            let name = String(title.dropFirst(parts[0].count).dropLast(parts[1].count)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                return name
            }
        }
        return nil
    }
}
