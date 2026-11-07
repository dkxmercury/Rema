import Foundation

public enum SearchField: Equatable, Sendable {
    case title
    case item(String)
    case place(String)
    case person(String)
}

public struct SearchHit: Identifiable, Equatable, Sendable {
    public let reminderID: UUID
    public let date: Date?
    public let done: Bool
    public let field: SearchField

    public var id: UUID { reminderID }
}

public struct SearchResults: Equatable, Sendable {
    public var upcoming: [SearchHit]
    public var earlier: [SearchHit]

    public static let empty = SearchResults(upcoming: [], earlier: [])

    public var count: Int {
        upcoming.count + earlier.count
    }
}

public enum ReminderSearch {
    public static func find(_ query: String, in reminders: [Reminder], places: [Place], people: (Reminder) -> [String] = { _ in [] }, now: Date, calendar: Calendar, locale: Locale? = nil) -> SearchResults {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return .empty }
        let names = Dictionary(places.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var upcoming: [SearchHit] = []
        var earlier: [SearchHit] = []
        for reminder in reminders where reminder.isLive {
            guard let field = field(of: reminder, needle: needle, places: names, people: people(reminder), locale: locale) else { continue }
            guard let schedule = reminder.schedule else {
                upcoming.append(SearchHit(reminderID: reminder.id, date: nil, done: false, field: field))
                continue
            }
            if let next = Recurrence.next(schedule, after: now.addingTimeInterval(-60), limit: 1, calendar: calendar).first,
               !(schedule.rule == nil && reminder.isDone(next)) {
                upcoming.append(SearchHit(reminderID: reminder.id, date: next, done: false, field: field))
            } else if let last = Recurrence.last(schedule, before: now, calendar: calendar) {
                earlier.append(SearchHit(reminderID: reminder.id, date: last, done: reminder.isDone(last), field: field))
            }
        }
        upcoming.sort { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        earlier.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return SearchResults(upcoming: upcoming, earlier: earlier)
    }

    public static func contains(_ text: String, _ needle: String, locale: Locale?) -> Bool {
        text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
    }

    private static func field(of reminder: Reminder, needle: String, places: [UUID: String], people: [String], locale: Locale?) -> SearchField? {
        if contains(reminder.title, needle, locale: locale) {
            return .title
        }
        if let item = reminder.items.first(where: { contains($0.text, needle, locale: locale) }) {
            return .item(item.text)
        }
        if let place = reminder.placeIDs.compactMap({ places[$0] }).first(where: { contains($0, needle, locale: locale) }) {
            return .place(place)
        }
        if let person = people.first(where: { contains($0, needle, locale: locale) }) {
            return .person(person)
        }
        return nil
    }
}

extension Recurrence {
    // The last two years are looked through first, so a repeat that ran more than a thousand times still gives its latest time.
    public static func last(_ schedule: Schedule, before now: Date, calendar: Calendar) -> Date? {
        let span: TimeInterval = 2 * 366 * 86_400
        if let recent = Recurrence.next(schedule, after: now.addingTimeInterval(-span), limit: 1000, calendar: calendar).last(where: { $0 < now }) {
            return recent
        }
        // Nothing in the last two years means the repeat is over, so its end says where to look.
        switch schedule.end {
        case .count(let total):
            return Recurrence.next(schedule, after: .distantPast, limit: total, calendar: calendar).last { $0 < now }
        case .until(let last):
            guard let end = calendar.date(from: DateComponents(year: last.year, month: last.month, day: last.day, hour: 23, minute: 59)) else { return nil }
            return Recurrence.next(schedule, after: end.addingTimeInterval(-span), limit: 1000, calendar: calendar).last { $0 < now }
        case .never:
            return Recurrence.next(schedule, after: .distantPast, limit: 1, calendar: calendar).last { $0 < now }
        }
    }
}
