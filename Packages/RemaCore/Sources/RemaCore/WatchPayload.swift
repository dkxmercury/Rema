import Foundation

public struct WatchItem: Codable, Hashable, Identifiable, Sendable {
    public let reminderID: UUID
    public let title: String
    public let occurrence: Date
    public var done: Bool
    public let urgent: Bool

    public var id: String {
        "\(reminderID.uuidString).\(Int(occurrence.timeIntervalSince1970))"
    }

    public init(reminderID: UUID, title: String, occurrence: Date, done: Bool, urgent: Bool) {
        self.reminderID = reminderID
        self.title = title
        self.occurrence = occurrence
        self.done = done
        self.urgent = urgent
    }
}

public struct WatchPayload: Codable, Hashable, Sendable {
    public var items: [WatchItem]
    public let generated: Date

    public init(items: [WatchItem], generated: Date) {
        self.items = items
        self.generated = generated
    }

    public static func make(reminders: [Reminder], now: Date, calendar: Calendar, days: Int = 2) -> WatchPayload {
        let active = reminders.filter(\.isLive)
        let byID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var items: [WatchItem] = []
        let start = calendar.startOfDay(for: now)
        for offset in 0..<max(1, days) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            for entry in Agenda.day(day, reminders: active, calendar: calendar) {
                guard let reminder = byID[entry.reminderID] else { continue }
                items.append(WatchItem(reminderID: reminder.id, title: reminder.title, occurrence: entry.occurrence, done: entry.done, urgent: reminder.urgent))
            }
        }
        return WatchPayload(items: items, generated: now)
    }

    public func today(_ now: Date, calendar: Calendar) -> [WatchItem] {
        items.filter { calendar.isDate($0.occurrence, inSameDayAs: now) }
    }

    public func next(after now: Date) -> WatchItem? {
        items.filter { !$0.done && $0.occurrence > now }.min { $0.occurrence < $1.occurrence }
    }
}
