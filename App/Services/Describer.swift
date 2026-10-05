import Foundation
import RemaCore

struct Describer {
    var calendar: Calendar = .current
    var locale: Locale = .current

    func subtitle(for reminder: Reminder, places: [Place]) -> String? {
        var parts: [String] = []
        if let rule = reminder.schedule?.rule {
            parts.append(repeatText(rule))
        }
        if reminder.urgent {
            parts.append(String(localized: "urgent"))
        }
        if let lead = reminder.preAlerts.sorted().first {
            parts.append(leadText(lead))
        }
        if reminder.nag {
            parts.append(String(localized: "persistent"))
        }
        if reminder.schedule == nil, !reminder.placeIDs.isEmpty {
            parts.append(placeText(reminder, places: places))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func repeatText(_ rule: RepeatRule) -> String {
        switch rule {
        case .daily:
            return String(localized: "every day")
        case .weekdays:
            return String(localized: "on weekdays")
        case .weekly(let days):
            let sorted = Set(days).sorted()
            if sorted.count == 7 { return String(localized: "every day") }
            if sorted == [.monday, .tuesday, .wednesday, .thursday, .friday] { return String(localized: "on weekdays") }
            return list(sorted.map(shortName))
        case .everyDays(let count):
            return String(localized: "every \(count) days")
        case .monthlyOnDay(let day):
            return String(localized: "monthly on day \(day)")
        case .monthlyOnWeekday:
            return String(localized: "every month")
        case .yearly:
            return String(localized: "every year")
        }
    }

    func leadText(_ minutes: Int) -> String {
        switch minutes {
        case 10_080: return String(localized: "a week before")
        case 1_440: return String(localized: "a day before")
        case 60: return String(localized: "an hour before")
        default:
            if minutes % 1_440 == 0 { return String(localized: "\(minutes / 1_440) days before") }
            if minutes % 60 == 0 { return String(localized: "\(minutes / 60) hours before") }
            return String(localized: "\(minutes) minutes before")
        }
    }

    func placeText(_ reminder: Reminder, places: [Place]) -> String {
        let names = reminder.placeIDs.compactMap { id in places.first { $0.id == id }?.name.lowercased(with: locale) }
        let trigger = reminder.placeTrigger == .leave ? String(localized: "leaving") : String(localized: "arriving")
        return "\(trigger): \(names.joined(separator: ", "))"
    }

    func countdown(from now: Date, to date: Date) -> String {
        let minutes = max(0, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes < 60 {
            return String(localized: "in \(minutes) min")
        }
        if minutes < 24 * 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? String(localized: "in \(hours) h") : String(localized: "in \(hours) h \(rest) min")
        }
        return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).day().month(.abbreviated))
    }

    func dayAndTime(_ date: Date, now: Date) -> String {
        let time = self.time(date)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "today at \(time)")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "tomorrow at \(time)")
        }
        let day = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated))
        return String(localized: "\(day) at \(time)")
    }

    func time(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    func dateLine(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide).day().month(.wide))
    }

    private func shortName(_ day: Weekday) -> String {
        var formatter = calendar
        formatter.locale = locale
        let symbols = formatter.shortStandaloneWeekdaySymbols
        return symbols[day.rawValue % 7].lowercased(with: locale)
    }

    private func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        if items.count == 2 {
            return String(localized: "\(items[0]) and \(items[1])")
        }
        return items.joined(separator: ", ")
    }
}
