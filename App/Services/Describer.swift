import Foundation
import RemaCore

struct Describer {
    var calendar: Calendar = .current
    var locale: Locale = .current

    func subtitle(for reminder: Reminder, places: [Place], withRepeat: Bool = true) -> String? {
        var parts: [String] = []
        if !reminder.items.isEmpty {
            parts.append(String(localized: "\(reminder.checkedCount) of \(reminder.items.count)", bundle: .app, locale: .app))
        }
        if withRepeat, let rule = reminder.schedule?.rule {
            parts.append(repeatText(rule))
        }
        if reminder.urgent {
            parts.append(String(localized: "urgent", bundle: .app, locale: .app))
        }
        if let lead = reminder.preAlerts.sorted().first {
            parts.append(leadText(lead))
        }
        if reminder.nag {
            parts.append(String(localized: "persistent", bundle: .app, locale: .app))
        }
        if reminder.schedule == nil, !reminder.placeIDs.isEmpty {
            parts.append(placeText(reminder, places: places))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func repeatText(_ rule: RepeatRule) -> String {
        switch rule {
        case .daily:
            return String(localized: "every day", bundle: .app, locale: .app)
        case .weekdays:
            return String(localized: "on weekdays", bundle: .app, locale: .app)
        case .weekly(let days):
            let sorted = Set(days).sorted()
            if sorted.count == 7 { return String(localized: "every day", bundle: .app, locale: .app) }
            if sorted == [.monday, .tuesday, .wednesday, .thursday, .friday] { return String(localized: "on weekdays", bundle: .app, locale: .app) }
            return list(sorted.map(shortName))
        case .everyDays(let count):
            return String(localized: "every \(count) days", bundle: .app, locale: .app)
        case .monthlyOnDay(let day):
            return String(localized: "monthly on day \(day)", bundle: .app, locale: .app)
        case .monthlyOnWeekday:
            return String(localized: "every month", bundle: .app, locale: .app)
        case .lastWorkday:
            return String(localized: "monthly, on the last working day", bundle: .app, locale: .app)
        case .everyMonths(let count):
            return count == 3 ? String(localized: "every quarter", bundle: .app, locale: .app) : String(localized: "every \(count) months", bundle: .app, locale: .app)
        case .evenDays:
            return String(localized: "on even dates", bundle: .app, locale: .app)
        case .oddDays:
            return String(localized: "on odd dates", bundle: .app, locale: .app)
        case .yearly:
            return String(localized: "every year", bundle: .app, locale: .app)
        }
    }

    func leadText(_ minutes: Int) -> String {
        switch minutes {
        case 10_080: return String(localized: "a week before", bundle: .app, locale: .app)
        case 1_440: return String(localized: "a day before", bundle: .app, locale: .app)
        case 60: return String(localized: "an hour before", bundle: .app, locale: .app)
        default:
            if minutes % 1_440 == 0 { return String(localized: "\(minutes / 1_440) days before", bundle: .app, locale: .app) }
            if minutes % 60 == 0 { return String(localized: "\(minutes / 60) hours before", bundle: .app, locale: .app) }
            return String(localized: "\(minutes) minutes before", bundle: .app, locale: .app)
        }
    }

    func placeText(_ reminder: Reminder, places: [Place]) -> String {
        let names = reminder.placeIDs.compactMap { id in places.first { $0.id == id }?.name.lowercased(with: locale) }
        let trigger = reminder.placeTrigger == .leave ? String(localized: "leaving", bundle: .app, locale: .app) : String(localized: "arriving", bundle: .app, locale: .app)
        return "\(trigger): \(names.joined(separator: ", "))"
    }

    func countdown(from now: Date, to date: Date) -> String {
        let minutes = max(0, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes < 60 {
            return String(localized: "in \(minutes) min", bundle: .app, locale: .app)
        }
        if minutes < 24 * 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? String(localized: "in \(hours) h", bundle: .app, locale: .app) : String(localized: "in \(hours) h \(rest) min", bundle: .app, locale: .app)
        }
        return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).day().month(.abbreviated))
    }

    func dayAndTime(_ date: Date, now: Date) -> String {
        let time = shortTime(date)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "today at \(time)", bundle: .app, locale: .app)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "tomorrow at \(time)", bundle: .app, locale: .app)
        }
        let day = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated))
        return String(localized: "\(day) at \(time)", bundle: .app, locale: .app)
    }

    func time(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    func shortTime(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    func shortMonth(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated)).replacingOccurrences(of: ".", with: "")
    }

    func dayTitle(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide).day().month(.wide)).capitalizedFirst(locale)
    }

    func fullDate(_ date: Date) -> String {
        "\(dayTitle(date)), \(shortTime(date))"
    }

    func repeatValue(_ schedule: Schedule?) -> String {
        guard let schedule, let rule = schedule.rule else { return String(localized: "No repeat", bundle: .app, locale: .app) }
        switch rule {
        case .yearly(let month, let day):
            let reference = calendar.date(from: DateComponents(year: 2000, month: month, day: day, hour: 12)) ?? Date()
            let date = reference.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)).replacingOccurrences(of: ".", with: "")
            return String(localized: "Every year, \(date)", bundle: .app, locale: .app)
        case .monthlyOnDay(let day):
            return String(localized: "Every month, day \(day)", bundle: .app, locale: .app)
        default:
            return repeatText(rule).capitalizedFirst(locale)
        }
    }

    func soundName(_ choice: SoundChoice, settings: Settings, sounds: [CustomSound]) -> String {
        switch choice {
        case .standard:
            return soundName(settings.defaultSound, settings: settings, sounds: sounds)
        case .builtIn(let id):
            return builtInName(BuiltInSound(rawValue: id) ?? .mechanika)
        case .custom(let id):
            return sounds.first { $0.id == id && $0.deletedAt == nil }?.name ?? builtInName(.mechanika)
        }
    }

    func builtInName(_ sound: BuiltInSound) -> String {
        switch sound {
        case .mechanika: return String(localized: "Mechanika", bundle: .app, locale: .app)
        case .bell: return String(localized: "Little bell", bundle: .app, locale: .app)
        case .drops: return String(localized: "Drops", bundle: .app, locale: .app)
        case .ticktock: return String(localized: "Tick-tock", bundle: .app, locale: .app)
        case .soft: return String(localized: "Soft", bundle: .app, locale: .app)
        case .silent: return String(localized: "No sound", bundle: .app, locale: .app)
        }
    }

    func dateLine(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide).day().month(.wide))
    }

    func weekdayList(_ days: [Weekday]) -> String {
        Set(days).sorted().map(shortName).joined(separator: ", ")
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
            return String(localized: "\(items[0]) and \(items[1])", bundle: .app, locale: .app)
        }
        return items.joined(separator: ", ")
    }
}

extension String {
    func capitalizedFirst(_ locale: Locale) -> String {
        guard let first else { return self }
        return String(first).uppercased(with: locale) + dropFirst()
    }
}

extension String {
    func quoted(in locale: Locale = .app) -> String {
        "\(locale.quotationBeginDelimiter ?? "“")\(self)\(locale.quotationEndDelimiter ?? "”")"
    }
}
