import RemaCore
import SwiftUI
import WidgetKit

struct DayEntry: TimelineEntry {
    let date: Date
    let content: HomeContent
    let nextOccurrence: Date?

    var rows: [HomeContent.Row] {
        content.rows
    }

    var doneCount: Int {
        rows.filter(\.done).count
    }

    var openRows: [HomeContent.Row] {
        rows.filter { !$0.done }
    }

    var laterToday: Int {
        guard let nextOccurrence else { return openRows.count }
        return openRows.filter { $0.occurrence > nextOccurrence }.count
    }

    var minutesLeft: Int? {
        nextOccurrence.map { max(0, Int(ceil($0.timeIntervalSince(date) / 60))) }
    }

    var placeLine: String? {
        content.tiles.first { $0.icon == .place }.map { "\($0.title) · \($0.subtitle)" }
    }

    var yearlyLine: String? {
        content.tiles.first { $0.icon == .yearly }.map { "\($0.subtitle.capitalizedFirst(.current)) · \($0.title)" }
    }

    static func make(at date: Date, snapshot: StoreSnapshot?) -> DayEntry {
        let reminders = snapshot?.reminders ?? []
        let places = snapshot?.places ?? []
        let content = HomeContent.make(reminders: reminders, places: places, now: date, calendar: .current, locale: .current)
        let active = reminders.filter { $0.deletedAt == nil }
        let next = Agenda.upcoming(after: date, reminders: active, calendar: .current, limit: 1).first
        return DayEntry(date: date, content: content, nextOccurrence: next?.occurrence)
    }

    static var sample: DayEntry {
        let next = SampleData.calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 14, minute: 30))
        return DayEntry(date: SampleData.now, content: SampleData.gallery, nextOccurrence: next)
    }
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
        } else {
            completion(.make(at: Date(), snapshot: SharedStore.load()))
        }
    }

    // A frame every five minutes keeps the hand moving; the exact minutes of reminders keep the list honest.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let snapshot = SharedStore.load()
        let now = Date()
        let start = Date(timeIntervalSinceReferenceDate: floor(now.timeIntervalSinceReferenceDate / 60) * 60)
        let end = start.addingTimeInterval(6 * 3600)
        var moments: Set<Date> = [start]
        var step = Date(timeIntervalSinceReferenceDate: ceil(start.timeIntervalSinceReferenceDate / 300) * 300)
        while step < end {
            moments.insert(step)
            step = step.addingTimeInterval(300)
        }
        for reminder in snapshot?.reminders ?? [] where reminder.deletedAt == nil {
            if let snoozed = reminder.snoozedUntil, snoozed > now, snoozed < end {
                moments.insert(Self.minute(snoozed))
            }
            guard let schedule = reminder.schedule else { continue }
            for occurrence in Recurrence.next(schedule, after: now, limit: 4, calendar: .current) where occurrence < end {
                moments.insert(Self.minute(occurrence))
                moments.insert(Self.minute(occurrence.addingTimeInterval(60)))
            }
        }
        let entries = moments.sorted().map { DayEntry.make(at: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static func minute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: floor(date.timeIntervalSinceReferenceDate / 60) * 60)
    }
}
