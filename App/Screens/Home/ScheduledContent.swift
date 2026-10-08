import Foundation
import RemaCore

// Everything after today: a repeat once, on its nearest day; monthly, yearly and by place apart.
struct ScheduledContent {
    struct Item: Identifiable {
        let id: String
        let reminderID: UUID
        let lead: String?
        var month: String?
        let title: String
        let subtitle: String?
    }

    struct Day: Identifiable {
        let id: Date
        let title: String
        var items: [Item]
    }

    let days: [Day]
    let monthly: [Item]
    let yearly: [Item]
    let places: [Item]
    let hasRepeats: Bool

    var isEmpty: Bool {
        days.isEmpty && monthly.isEmpty && yearly.isEmpty && places.isEmpty
    }

    static func make(reminders: [Reminder], places: [Place], now: Date, calendar: Calendar, locale: Locale, withPlaces: Bool = true) -> ScheduledContent {
        let describer = Describer(calendar: calendar, locale: locale)
        let active = reminders.filter { $0.deletedAt == nil }
        let byID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var days: [Day] = []
        var monthly: [Item] = []
        var yearly: [Item] = []
        var hasRepeats = false
        for item in upcoming(active, now: now, calendar: calendar) {
            guard let reminder = byID[item.reminderID] else { continue }
            let id = "\(reminder.id.uuidString)-\(Int(item.occurrence.timeIntervalSince1970))"
            switch reminder.schedule?.rule {
            case .yearly, .monthlyOnDay, .monthlyOnWeekday, .lastWorkday:
                let details = [describer.time(item.occurrence), describer.subtitle(for: reminder, places: places, withRepeat: false)].compactMap { $0 }
                let entry = Item(id: id, reminderID: reminder.id, lead: String(calendar.component(.day, from: item.occurrence)), month: describer.shortMonth(item.occurrence), title: reminder.title, subtitle: details.joined(separator: " · "))
                if case .yearly = reminder.schedule?.rule {
                    yearly.append(entry)
                } else {
                    monthly.append(entry)
                }
            default:
                hasRepeats = hasRepeats || reminder.schedule?.rule != nil
                let entry = Item(id: id, reminderID: reminder.id, lead: describer.time(item.occurrence), title: reminder.title, subtitle: describer.subtitle(for: reminder, places: places))
                let day = calendar.startOfDay(for: item.occurrence)
                if days.last?.id == day {
                    days[days.count - 1].items.append(entry)
                } else {
                    days.append(Day(id: day, title: describer.dateLine(item.occurrence), items: [entry]))
                }
            }
        }
        let placed = (withPlaces ? byPlace(active) : []).map { reminder in
            Item(id: reminder.id.uuidString, reminderID: reminder.id, lead: nil, title: reminder.title, subtitle: describer.placeText(reminder, places: places))
        }
        return ScheduledContent(days: days, monthly: monthly, yearly: yearly, places: placed, hasRepeats: hasRepeats)
    }

    static func count(reminders: [Reminder], now: Date, calendar: Calendar, withPlaces: Bool = true) -> Int {
        let active = reminders.filter { $0.deletedAt == nil }
        return upcoming(active, now: now, calendar: calendar).count + (withPlaces ? byPlace(active).count : 0)
    }

    private static func upcoming(_ reminders: [Reminder], now: Date, calendar: Calendar) -> [AgendaItem] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return Agenda.upcoming(after: tomorrow.addingTimeInterval(-1), reminders: reminders, calendar: calendar, limit: .max)
    }

    private static func byPlace(_ reminders: [Reminder]) -> [Reminder] {
        reminders.filter { $0.isPlaceOnly && $0.completedThrough == nil }
    }
}
