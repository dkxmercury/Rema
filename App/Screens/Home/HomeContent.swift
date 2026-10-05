import Foundation
import RemaCore

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
}

extension HomeContent {
    static func make(reminders: [Reminder], places: [Place], now: Date, calendar: Calendar, locale: Locale) -> HomeContent {
        let describer = Describer(calendar: calendar, locale: locale)
        let active = reminders.filter { $0.deletedAt == nil }
        let byID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let today = Agenda.day(now, reminders: active, calendar: calendar)
        let upcoming = Agenda.upcoming(after: now, reminders: active, calendar: calendar)
        let nextItem = upcoming.first
        let clock = calendar.dateComponents([.hour, .minute], from: now)

        func isNext(_ item: AgendaItem) -> Bool {
            item.reminderID == nextItem?.reminderID && item.occurrence == nextItem?.occurrence
        }

        let markers = today.enumerated().map { index, item -> DialMarker in
            let parts = calendar.dateComponents([.hour, .minute], from: item.occurrence)
            let kind: DialMarker.Kind = item.done ? .done : (isNext(item) ? .next : .upcoming)
            return DialMarker(id: index, hour: parts.hour ?? 0, minute: parts.minute ?? 0, kind: kind)
        }

        let rows = today.compactMap { item -> Row? in
            guard let reminder = byID[item.reminderID] else { return nil }
            return Row(
                id: "\(item.reminderID.uuidString)-\(Int(item.occurrence.timeIntervalSince1970))",
                reminderID: item.reminderID,
                occurrence: item.occurrence,
                time: describer.time(item.occurrence),
                title: reminder.title,
                subtitle: describer.subtitle(for: reminder, places: places),
                done: item.done,
                highlighted: isNext(item)
            )
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
                note: pending.map { String(localized: "I'll also remind \(describer.leadText($0))") },
                urgent: reminder.urgent
            )
        }

        var tiles: [Tile] = []
        if let parcel = active.first(where: { $0.isPlaceOnly && $0.completedThrough == nil }) {
            tiles.append(Tile(
                id: "place-\(parcel.id.uuidString)",
                reminderID: parcel.id,
                icon: .place,
                label: String(localized: "By place"),
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
                label: String(localized: "Every year"),
                title: reminder.title,
                subtitle: describer.dayAndTime(yearly.occurrence, now: now)
            ))
        }

        return HomeContent(
            dateLine: describer.dateLine(now),
            nowHour: clock.hour ?? 0,
            nowMinute: clock.minute ?? 0,
            nowText: describer.time(now),
            markers: markers,
            next: next,
            rows: rows,
            tiles: tiles
        )
    }
}

enum SampleData {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        calendar.locale = Locale(identifier: "ru_RU")
        return calendar
    }()

    static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 13, minute: 50))!

    static let work = Place(name: "Работа", icon: "work", latitude: 41.311, longitude: 69.279, radius: 200, createdAt: now)
    static let gym = Place(name: "Спортзал", icon: "sport", latitude: 41.299, longitude: 69.240, radius: 100, createdAt: now)

    static var places: [Place] { [work, gym] }

    static var reminders: [Reminder] {
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
            Reminder(title: "Оплатить сервер", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 6), time: LocalTime(hour: 10, minute: 0), rule: .yearly(month: 10, day: 6)), preAlerts: [10_080, 1_440], nag: true, urgent: true, createdAt: now),
        ]
    }

    static var home: HomeContent {
        HomeContent.make(reminders: reminders, places: places, now: now, calendar: calendar, locale: Locale(identifier: "ru_RU"))
    }
}
