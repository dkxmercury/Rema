import EventKit
import Foundation
import Observation

// Events of the iPhone calendar shown next to reminders; only read, Rema never writes into the calendar.
@MainActor
@Observable
final class CalendarFeed {
    static let shared = CalendarFeed()
    private static let enabledKey = "calendar.enabled"

    private(set) var enabled: Bool
    private(set) var revision = 0
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var cache: (key: [Int], entries: [CalendarEntry])?

    private init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey) && Self.authorized
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.revision += 1 }
        }
    }

    static var authorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    // Read from iOS each time, so a refusal is still known after a restart and a later permission in Settings shows up.
    var denied: Bool {
        _ = revision
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted || status == .writeOnly
    }

    func setEnabled(_ on: Bool) async {
        if on {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            enabled = granted
        } else {
            enabled = false
        }
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        revision += 1
    }

    // Screens ask on every redraw; the calendar is read again only for a new span or after it changed.
    func entries(from start: Date, to end: Date) -> [CalendarEntry] {
        guard enabled, Self.authorized, start < end else { return [] }
        let key = [Int(start.timeIntervalSince1970 / 60), Int(end.timeIntervalSince1970 / 60), revision]
        if let cache, cache.key == key {
            return cache.entries
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let entries = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { CalendarEntry(id: "\($0.eventIdentifier ?? UUID().uuidString)-\(Int($0.startDate.timeIntervalSince1970))", title: $0.title ?? "", start: $0.startDate, end: $0.endDate) }
            .sorted { $0.start < $1.start }
        cache = (key, entries)
        return entries
    }

    // A meeting that began yesterday evening is not one of today's.
    func day(_ date: Date, calendar: Calendar = .current) -> [CalendarEntry] {
        let start = calendar.startOfDay(for: date)
        return entries(from: start, to: calendar.date(byAdding: .day, value: 1, to: start) ?? start).filter { $0.start >= start }
    }
}
