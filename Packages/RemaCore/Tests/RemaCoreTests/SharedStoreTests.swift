import Foundation
import Testing
@testable import RemaCore

struct SharedStoreTests {
    let created = Date(timeIntervalSince1970: 1_790_000_000)

    func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func snapshot(_ reminders: [Reminder]) -> StoreSnapshot {
        StoreSnapshot(reminders: reminders, places: [], settings: .standard(at: created), sounds: nil)
    }

    @Test func savedSnapshotLoadsBack() throws {
        let directory = folder()
        let call = Reminder(title: "Позвонить", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 14, minute: 30)), createdAt: created)
        try SharedStore.save(snapshot([call]), to: directory)
        let loaded = try #require(SharedStore.load(from: directory))
        #expect(loaded.reminders == [call])
        #expect(SharedStore.modified(in: directory) != nil)
    }

    @Test func missingFileGivesNothing() {
        #expect(SharedStore.load(from: folder()) == nil)
    }

    @Test func doneAndUndoneChangeOnlyThatReminder() throws {
        let directory = folder()
        let call = Reminder(title: "Позвонить", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 14, minute: 30)), createdAt: created)
        let bread = Reminder(title: "Хлеб", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 19, minute: 0)), createdAt: created)
        try SharedStore.save(snapshot([call, bread]), to: directory)
        let occurrence = created.addingTimeInterval(3_600)

        #expect(SharedStore.setDone(true, reminder: call.id, occurrence: occurrence, in: directory, now: created))
        var loaded = try #require(SharedStore.load(from: directory))
        #expect(loaded.reminders[0].completedThrough == occurrence)
        #expect(loaded.reminders[1].completedThrough == nil)

        #expect(SharedStore.setDone(false, reminder: call.id, occurrence: occurrence, in: directory, now: created))
        loaded = try #require(SharedStore.load(from: directory))
        #expect(loaded.reminders[0].completedThrough == occurrence.addingTimeInterval(-1))
    }

    @Test func snoozeSetsTheTime() throws {
        let directory = folder()
        let call = Reminder(title: "Позвонить", schedule: nil, createdAt: created)
        try SharedStore.save(snapshot([call]), to: directory)
        let later = created.addingTimeInterval(600)
        #expect(SharedStore.snooze(reminder: call.id, until: later, in: directory, now: created))
        #expect(SharedStore.load(from: directory)?.reminders.first?.snoozedUntil == later)
        #expect(!SharedStore.snooze(reminder: UUID(), until: later, in: directory, now: created))
    }
}
