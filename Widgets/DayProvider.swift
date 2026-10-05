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
        return DayEntry(date: SampleData.now, content: SampleData.home, nextOccurrence: next)
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

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let snapshot = SharedStore.load()
        let now = Date()
        let start = Date(timeIntervalSinceReferenceDate: floor(now.timeIntervalSinceReferenceDate / 60) * 60)
        let entries = (0..<90).map { DayEntry.make(at: start.addingTimeInterval(Double($0) * 60), snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
