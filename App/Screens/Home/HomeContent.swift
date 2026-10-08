import Foundation
import RemaCore

struct CalendarEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
}

struct HomeContent {
    struct Row: Identifiable {
        let id: String
        let reminderID: UUID
        let occurrence: Date
        let time: String
        let title: String
        let subtitle: String?
        let done: Bool
        let highlighted: Bool
        var missed = false
    }

    struct Event: Identifiable {
        let id: String
        let start: Date
        let end: Date
        let time: String
        let title: String
        let subtitle: String
        let upcoming: Bool
        let reminded: Bool
    }

    struct Tile: Identifiable {
        enum Icon {
            case place
            case yearly
        }

        let id: String
        let reminderID: UUID
        let icon: Icon
        let label: String
        let title: String
        let subtitle: String
    }

    struct Next {
        let reminderID: UUID
        let time: String
        let countdown: String
        let title: String
        let note: String?
        let urgent: Bool
    }

    let dateLine: String
    let nowHour: Int
    let nowMinute: Int
    let nowText: String
    let markers: [DialMarker]
    let next: Next?
    let rows: [Row]
    let tiles: [Tile]
    var missedCount = 0
    var events: [Event] = []
}

extension HomeContent {
    // A meeting becomes a reminder under its own name cut to what the server takes, or under a plain name when it has none.
    static func reminderTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Event from the calendar", bundle: .app, locale: .app) : String(trimmed.prefix(Reminder.maximumTitleLength))
    }

    static func make(reminders: [Reminder], places: [Place], now: Date, calendar: Calendar, locale: Locale, missed showsMissed: Bool = false, events entries: [CalendarEntry] = []) -> HomeContent {
        let describer = Describer(calendar: calendar, locale: locale)
        let active = reminders.filter { $0.deletedAt == nil }
        let byID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let today = Agenda.day(now, reminders: active, calendar: calendar)
        let missed = showsMissed ? Agenda.missed(now, reminders: active, calendar: calendar) : []

        func isMissed(_ item: AgendaItem) -> Bool {
            missed.contains { $0.reminderID == item.reminderID && $0.occurrence == item.occurrence }
        }
        let upcoming = Agenda.upcoming(after: now, reminders: active, calendar: calendar)
        let nextItem = upcoming.first
        let clock = calendar.dateComponents([.hour, .minute], from: now)

        func isNext(_ item: AgendaItem) -> Bool {
            item.reminderID == nextItem?.reminderID && item.occurrence == nextItem?.occurrence
        }

        let markers = today.enumerated().map { index, item -> DialMarker in
            let parts = calendar.dateComponents([.hour, .minute], from: item.occurrence)
            let kind: DialMarker.Kind = item.done ? .done : (isMissed(item) ? .missed : (isNext(item) ? .next : .upcoming))
            let movable = !item.done && byID[item.reminderID].map { $0.schedule?.rule == nil } == true
            return DialMarker(id: index, hour: parts.hour ?? 0, minute: parts.minute ?? 0, kind: kind, reminderID: item.reminderID, occurrence: item.occurrence, movable: movable)
        }

        let eventMarkers = entries.enumerated().map { index, entry -> DialMarker in
            let parts = calendar.dateComponents([.hour, .minute], from: entry.start)
            return DialMarker(id: 10_000 + index, hour: parts.hour ?? 0, minute: parts.minute ?? 0, kind: .event)
        }
        let events = entries.map { entry in
            Event(
                id: entry.id,
                start: entry.start,
                end: entry.end,
                time: describer.time(entry.start),
                title: entry.title,
                subtitle: String(localized: "calendar · until \(describer.time(entry.end))", bundle: .app, locale: .app),
                upcoming: entry.start > now,
                reminded: active.contains { reminder in
                    guard reminder.title == reminderTitle(entry.title), let schedule = reminder.schedule else { return false }
                    let start = calendar.dateInterval(of: .minute, for: entry.start)?.start ?? entry.start
                    return calendar.date(from: DateComponents(year: schedule.start.year, month: schedule.start.month, day: schedule.start.day, hour: schedule.time.hour, minute: schedule.time.minute)) == start
                }
            )
        }

        let rows = today.compactMap { item -> Row? in
            byID[item.reminderID].map { row(item, reminder: $0, places: places, describer: describer, highlighted: isNext(item), missed: isMissed(item)) }
        }

        var next: Next?
        if let item = nextItem, let reminder = byID[item.reminderID] {
            let pending = reminder.preAlerts
                .filter { item.occurrence.addingTimeInterval(-Double($0) * 60) > now }
                .min()
            next = Next(
                reminderID: reminder.id,
                time: describer.time(item.occurrence),
                countdown: describer.countdown(from: now, to: item.occurrence),
                title: reminder.title,
                note: pending.map { String(localized: "I'll also remind \(describer.leadText($0))", bundle: .app, locale: .app) },
                urgent: reminder.urgent
            )
        }

        var tiles: [Tile] = []
        if let parcel = active.first(where: { $0.isPlaceOnly && $0.completedThrough == nil }) {
            tiles.append(Tile(
                id: "place-\(parcel.id.uuidString)",
                reminderID: parcel.id,
                icon: .place,
                label: String(localized: "By place", bundle: .app, locale: .app),
                title: parcel.title,
                subtitle: describer.placeText(parcel, places: places)
            ))
        }
        let todayIDs = Set(today.map(\.reminderID))
        if let yearly = upcoming.first(where: { item in
            guard case .yearly = byID[item.reminderID]?.schedule?.rule else { return false }
            return !todayIDs.contains(item.reminderID)
        }), let reminder = byID[yearly.reminderID] {
            tiles.append(Tile(
                id: "yearly-\(reminder.id.uuidString)",
                reminderID: reminder.id,
                icon: .yearly,
                label: String(localized: "Every year", bundle: .app, locale: .app),
                title: reminder.title,
                subtitle: describer.dayAndTime(yearly.occurrence, now: now)
            ))
        }

        return HomeContent(
            dateLine: describer.dateLine(now),
            nowHour: clock.hour ?? 0,
            nowMinute: clock.minute ?? 0,
            nowText: describer.time(now),
            markers: eventMarkers + markers,
            next: next,
            rows: rows,
            tiles: tiles,
            missedCount: missed.count,
            events: events
        )
    }
}

extension HomeContent {
    static func rows(on day: Date, reminders: [Reminder], places: [Place], now: Date, calendar: Calendar, locale: Locale, missed showsMissed: Bool = false) -> [Row] {
        let describer = Describer(calendar: calendar, locale: locale)
        let active = reminders.filter { $0.deletedAt == nil }
        let byID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let next = Agenda.upcoming(after: now, reminders: active, calendar: calendar).first
        let missed = showsMissed && calendar.isDate(day, inSameDayAs: now) ? Agenda.missed(now, reminders: active, calendar: calendar) : []
        return Agenda.day(day, reminders: active, calendar: calendar).compactMap { item in
            byID[item.reminderID].map {
                row(
                    item,
                    reminder: $0,
                    places: places,
                    describer: describer,
                    highlighted: item.reminderID == next?.reminderID && item.occurrence == next?.occurrence,
                    missed: missed.contains { $0.reminderID == item.reminderID && $0.occurrence == item.occurrence }
                )
            }
        }
    }

    private static func row(_ item: AgendaItem, reminder: Reminder, places: [Place], describer: Describer, highlighted: Bool, missed: Bool = false) -> Row {
        Row(
            id: "\(item.reminderID.uuidString)-\(Int(item.occurrence.timeIntervalSince1970))",
            reminderID: item.reminderID,
            occurrence: item.occurrence,
            time: describer.time(item.occurrence),
            title: reminder.title,
            subtitle: describer.subtitle(for: reminder, places: places),
            done: item.done,
            highlighted: highlighted,
            missed: missed
        )
    }
}

enum SampleData {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.firstWeekday = 2
        return calendar
    }()

    static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 13, minute: 50))!

    static let work = Place(name: "Работа", icon: "work", latitude: 41.311, longitude: 69.279, radius: 200, createdAt: now)
    static let gym = Place(name: "Спортзал", icon: "sport", latitude: 41.299, longitude: 69.240, radius: 100, createdAt: now)

    static var places: [Place] { [work, gym] }

    static let gong = CustomSound(name: "гонг.mp3", duration: 8, createdAt: now)

    static let server = Reminder(
        title: "Оплатить сервер",
        schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 6), time: LocalTime(hour: 10, minute: 0), rule: .yearly(month: 10, day: 6)),
        preAlerts: [10_080, 1_440],
        nag: true,
        urgent: true,
        sound: .custom(gong.id),
        createdAt: now
    )

    static let reminders: [Reminder] = {
        var vitamins = Reminder(
            title: "Выпить витамины",
            schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 1), time: LocalTime(hour: 9, minute: 0), rule: .daily),
            nag: true,
            createdAt: now
        )
        vitamins.completedThrough = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9, minute: 0))
        return [
            vitamins,
            Reminder(title: "Позвонить поставщику", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 14, minute: 30)), preAlerts: [15], urgent: true, createdAt: now),
            Reminder(title: "Купить хлеб и молоко", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 19, minute: 0)), createdAt: now),
            Reminder(title: "Полить цветы", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 1), time: LocalTime(hour: 21, minute: 30), rule: .weekly([.monday, .thursday])), createdAt: now),
            Reminder(title: "Забрать посылку", schedule: nil, placeIDs: [work.id, gym.id], placeTrigger: .leave, createdAt: now),
            server,
        ]
    }()

    static let groceries = Reminder(
        title: "Купить продукты",
        schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 19, minute: 0)),
        items: [
            ChecklistItem(text: "Хлеб", done: true),
            ChecklistItem(text: "Молоко 2 л"),
            ChecklistItem(text: "Яйца 10 шт"),
            ChecklistItem(text: "Сыр"),
        ],
        createdAt: now
    )

    static var monthlyReport: Reminder {
        Reminder(title: "Сдать отчёт", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 10, minute: 0), rule: .lastWorkday), createdAt: now)
    }

    // Ticks of the last days, for the history.
    static var withHistory: [Reminder] {
        var list = reminders
        for offset in 0..<12 {
            let day = calendar.date(byAdding: .day, value: -offset, to: now)!
            let occurrence = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
            list[0].markDone(through: occurrence, at: occurrence.addingTimeInterval(120))
        }
        for (month, day) in [(9, 21), (9, 24), (9, 28), (10, 1)] {
            let occurrence = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 21, minute: 30))!
            list[3].markDone(through: occurrence, at: occurrence.addingTimeInterval(300))
        }
        return list
    }

    // A day longer than the screen, for the scrolling check.
    static var busyDay: [Reminder] {
        let day = LocalDate(year: 2026, month: 10, day: 5)
        return (0..<24).map { index in
            let title = index == 0 ? String(repeating: "Очень длинное название напоминания ", count: 6) : "Дело \(index + 1)"
            return Reminder(title: title, schedule: Schedule(start: day, time: LocalTime(hour: 14 + index / 4, minute: index % 4 * 15)), createdAt: now)
        }
    }

    static var home: HomeContent {
        HomeContent.make(reminders: reminders, places: places, now: now, calendar: calendar, locale: Locale(identifier: "ru_RU"))
    }

    // The widget gallery speaks the phone's language, the Russian sample above stays for the design checks.
    static var gallery: HomeContent {
        let names = [
            String(localized: "Take vitamins", bundle: .app, locale: .app),
            String(localized: "Call the supplier", bundle: .app, locale: .app),
            String(localized: "Buy bread and milk", bundle: .app, locale: .app),
            String(localized: "Water the plants", bundle: .app, locale: .app),
            String(localized: "Pick up the parcel", bundle: .app, locale: .app),
            String(localized: "Renew the domain", bundle: .app, locale: .app),
        ]
        var list = reminders
        for index in list.indices where index < names.count {
            list[index].title = names[index]
        }
        var spots = places
        spots[0].name = String(localized: "Work", bundle: .app, locale: .app)
        spots[1].name = String(localized: "Gym", bundle: .app, locale: .app)
        var local = calendar
        local.locale = .app
        local.firstWeekday = Calendar.current.firstWeekday
        return HomeContent.make(reminders: list, places: spots, now: now, calendar: local, locale: .app)
    }
}
