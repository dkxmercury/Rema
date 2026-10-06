import Foundation

public enum EarlyReason: String, Equatable, Sendable {
    case medical
    case travel
    case birthday
}

public struct EarlySuggestion: Equatable, Sendable {
    public let minutes: Int
    public let reason: EarlyReason
}

public struct HabitSuggestion: Equatable, Sendable {
    public let reminderID: UUID
    public let title: String
    public let weekday: Weekday
    public let key: String
}

public enum Suggestions {
    private static let stems: [(EarlyReason, [String])] = [
        (.birthday, [
            "день рождения", "днюх", "юбилей", "день народження", "ювілей", "birthday", "anniversary",
            "tug'ilgan kun", "туғилган кун", "عيد ميلاد", "anniversaire", "geburtstag", "jubiläum",
        ]),
        (.medical, [
            "врач", "доктор", "стоматолог", "дантист", "клиник", "больниц", "поликлиник", "анализ", "приём",
            "лікар", "клінік", "лікарн", "аналіз", "прийом",
            "doctor", "dentist", "clinic", "hospital", "appointment", "checkup",
            "shifokor", "doktor", "stomatolog", "klinika", "kasalxona", "poliklinika", "шифокор", "клиника", "касалхона",
            "طبيب", "دكتور", "أسنان", "عيادة", "مستشفى",
            "médecin", "docteur", "dentiste", "clinique", "hôpital", "rdv=",
            "arzt", "ärztin", "zahnarzt", "klinik", "krankenhaus",
        ]),
        (.travel, [
            "поезд", "самолёт", "рейс", "вылет", "аэропорт", "вокзал", "электричк",
            "потяг", "поїзд", "літак", "виліт", "аеропорт",
            "train=", "flight", "plane=", "airport",
            "poyezd", "samolyot", "reys", "aeroport", "vokzal", "самолет", "аэропорт",
            "قطار", "طائرة", "رحلة", "مطار",
            "vol=", "avion", "aéroport", "gare=",
            "zug=", "flug=", "flugzeug", "flughafen", "bahnhof",
        ]),
    ]

    public static func early(title: String, when: Date, preAlerts: [Int], now: Date) -> EarlySuggestion? {
        guard preAlerts.isEmpty, let reason = reason(for: title) else { return nil }
        let hours = when.timeIntervalSince(now) / 3600
        if hours >= 24.5 {
            return EarlySuggestion(minutes: 1_440, reason: reason)
        }
        if hours >= 3, reason != .birthday {
            return EarlySuggestion(minutes: 120, reason: reason)
        }
        return nil
    }

    public static func reason(for title: String) -> EarlyReason? {
        let text = fold(title)
        let words = Set(text.split { !$0.isLetter && $0 != "'" && $0 != "-" }.map(String.init))
        for (reason, list) in stems {
            for entry in list {
                let exact = entry.hasSuffix("=")
                let stem = fold(exact ? String(entry.dropLast()) : entry)
                if stem.contains(" ") || stem.unicodeScalars.contains(where: { (0x0600...0x06FF).contains($0.value) }) {
                    if text.contains(stem) {
                        return reason
                    }
                } else if exact {
                    if words.contains(stem) {
                        return reason
                    }
                } else if words.contains(where: { $0.hasPrefix(stem) }) {
                    return reason
                }
            }
        }
        return nil
    }

    // Three one-off reminders with the same title on the same weekday, a week apart, the last one still ahead.
    public static func habit(in reminders: [Reminder], now: Date, calendar: Calendar, dismissed: Set<String>) -> HabitSuggestion? {
        let today = LocalDate(now, in: calendar)
        var groups: [String: [(date: LocalDate, reminder: Reminder)]] = [:]
        var repeating = Set<String>()
        for reminder in reminders {
            guard let schedule = reminder.schedule else { continue }
            let title = fold(reminder.title).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            if schedule.rule != nil {
                if reminder.deletedAt == nil {
                    repeating.insert(title)
                }
                continue
            }
            groups["\(title)|\(schedule.start.weekday.rawValue)", default: []].append((schedule.start, reminder))
        }
        var best: HabitSuggestion?
        var bestDate: LocalDate?
        for (key, items) in groups where !dismissed.contains(key) {
            let title = String(key.split(separator: "|").first ?? "")
            guard !repeating.contains(title) else { continue }
            let sorted = items.sorted { $0.date < $1.date }
            guard let last = sorted.last, last.reminder.deletedAt == nil, last.date >= today else { continue }
            let dates = Set(sorted.map(\.date))
            guard dates.contains(last.date.adding(days: -7)), dates.contains(last.date.adding(days: -14)) else { continue }
            if bestDate.map({ last.date < $0 }) ?? true {
                best = HabitSuggestion(reminderID: last.reminder.id, title: last.reminder.title, weekday: last.date.weekday, key: key)
                bestDate = last.date
            }
        }
        return best
    }

    static func fold(_ text: String) -> String {
        var result = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        for mark in ["‘", "’", "ʻ", "ʼ", "`"] {
            result = result.replacingOccurrences(of: mark, with: "'")
        }
        return result
    }
}
