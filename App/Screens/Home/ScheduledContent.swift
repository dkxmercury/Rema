import Foundation
import RemaCore

// Everything after today: a repeat once, on its nearest day, and reminders by place apart.
struct ScheduledContent {
    struct Item: Identifiable {
        let id: String
        let reminderID: UUID
        let time: String?
        let title: String
        let subtitle: String?
    }

    struct Day: Identifiable {
        let id: Date
        let title: String
        var items: [Item]
    }

    let days: [Day]
    let places: [Item]
    let hasRepeats: Bool

    var isEmpty: Bool {
        days.isEmpty && places.isEmpty
    }

    static func make(reminders: [Reminder], places: [Place], now: Date, calendar: Calendar, locale: Locale) -> ScheduledContent {
        let describer = Describer(calendar: calendar, locale: locale)
        let active = reminders.filter { $0.deletedAt == nil }
        let byID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var days: [Day] = []
        var hasRepeats = false
        for item in upcoming(active, now: now, calendar: calendar) {
            guard let reminder = byID[item.reminderID] else { continue }
            hasRepeats = hasRepeats || reminder.schedule?.rule != nil
            let entry = Item(
                id: "\(reminder.id.uuidString)-\(Int(item.occurrence.timeIntervalSince1970))",
                reminderID: reminder.id,
                time: describer.time(item.occurrence),
                title: reminder.title,
                subtitle: describer.subtitle(for: reminder, places: places)
            )
            let day = calendar.startOfDay(for: item.occurrence)
            if days.last?.id == day {
                days[days.count - 1].items.append(entry)
            } else {
                days.append(Day(id: day, title: describer.dateLine(item.occurrence), items: [entry]))
            }
        }
        let placed = byPlace(active).map { reminder in
            Item(id: reminder.id.uuidString, reminderID: reminder.id, time: nil, title: reminder.title, subtitle: describer.placeText(reminder, places: places))
        }
        return ScheduledContent(days: days, places: placed, hasRepeats: hasRepeats)
    }

    static func count(reminders: [Reminder], now: Date, calendar: Calendar) -> Int {
        let active = reminders.filter { $0.deletedAt == nil }
        return upcoming(active, now: now, calendar: calendar).count + byPlace(active).count
    }

    private static func upcoming(_ reminders: [Reminder], now: Date, calendar: Calendar) -> [AgendaItem] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return Agenda.upcoming(after: tomorrow.addingTimeInterval(-1), reminders: reminders, calendar: calendar, limit: .max)
    }

    private static func byPlace(_ reminders: [Reminder]) -> [Reminder] {
        reminders.filter { $0.isPlaceOnly && $0.completedThrough == nil }
    }
}
