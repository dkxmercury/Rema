import Foundation
import RemaCore

// What was ticked in the last month, by day, with the repeats kept up in a row on top.
struct DoneContent {
    struct Streak: Identifiable {
        let id: UUID
        let title: String
        let text: String
        let recent: [Bool]
    }

    struct Row: Identifiable {
        let id: String
        let reminderID: UUID
        let time: String
        let title: String
    }

    struct Day: Identifiable {
        let id: Date
        let title: String
        var rows: [Row]
    }

    let streaks: [Streak]
    let days: [Day]

    var isEmpty: Bool {
        streaks.isEmpty && days.isEmpty
    }

    static let empty = DoneContent(streaks: [], days: [])

    static func make(reminders: [Reminder], now: Date, calendar: Calendar, locale: Locale) -> DoneContent {
        let describer = Describer(calendar: calendar, locale: locale)
        let streaks = History.streaks(reminders, now: now, calendar: calendar).map { streak in
            Streak(
                id: streak.reminderID,
                title: streak.title,
                text: streak.daily ? String(localized: "\(streak.count) days in a row", bundle: .app, locale: .app) : String(localized: "\(streak.count) times in a row", bundle: .app, locale: .app),
                recent: streak.recent
            )
        }
        let start = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: now)) ?? now
        var days: [Day] = []
        for entry in History.entries(reminders, since: start) {
            let day = calendar.startOfDay(for: entry.at)
            let row = Row(id: "\(entry.reminderID.uuidString)-\(Int(entry.occurrence.timeIntervalSince1970))", reminderID: entry.reminderID, time: describer.time(entry.at), title: entry.title)
            if days.last?.id == day {
                days[days.count - 1].rows.insert(row, at: 0)
            } else {
                days.append(Day(id: day, title: title(of: day, now: now, calendar: calendar, describer: describer), rows: [row]))
            }
        }
        return DoneContent(streaks: streaks, days: days)
    }

    private static func title(of day: Date, now: Date, calendar: Calendar, describer: Describer) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return String(localized: "Today", bundle: .app, locale: .app)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            let date = day.formatted(Date.FormatStyle(locale: describer.locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.wide))
            return String(localized: "Yesterday, \(date)", bundle: .app, locale: .app)
        }
        return describer.dateLine(day)
    }
}
