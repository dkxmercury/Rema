import Foundation
import Testing
@testable import RemaCore

struct OlderBuildTests {
    let created = Date(timeIntervalSince1970: 1_790_000_000)

    func day(_ index: Int) -> Date {
        created.addingTimeInterval(Double(index) * 86_400)
    }

    func listReminder() -> Reminder {
        var reminder = Reminder(
            title: "Продукты",
            schedule: Schedule(start: LocalDate(year: 2026, month: 9, day: 21), time: LocalTime(hour: 9, minute: 0), rule: .daily),
            items: [ChecklistItem(text: "Хлеб"), ChecklistItem(text: "Молоко", done: true)],
            doneWhenChecked: false,
            contact: ContactLink(name: "Мама", phone: "1234"),
            createdAt: created
        )
        reminder.markDone(through: day(1), at: day(1))
        reminder.items[1].done = true
        return reminder
    }

    func withoutNewFields(_ reminder: Reminder) throws -> JSONValue {
        guard case .object(var fields) = try JSONValue(encoding: reminder) else { return .null }
        for key in ["items", "history", "contact", "doneWhenChecked"] {
            fields[key] = nil
        }
        return .object(fields)
    }

    func merge(_ local: Reminder, with data: JSONValue, at stamp: Int64) -> SyncMerge.Outcome {
        let key = SyncState.key(.reminders, local.id.uuidString)
        let state = SyncState(known: [key: SyncStamp.of(local.updatedAt)])
        let record = SyncRecord(kind: SyncKind.reminders.rawValue, clientId: local.id.uuidString, data: data, clientUpdatedAt: stamp, deleted: false, seq: 1)
        let response = SyncResponse(records: [record], rejected: [], cursor: 1, more: false)
        let snapshot = StoreSnapshot(reminders: [local], places: [], settings: .standard(at: created), sounds: nil)
        return SyncMerge.apply(response, sent: [], to: snapshot, state: state, now: created)
    }

    @Test func olderBuildKeepsTheListTheTicksAndTheContact() throws {
        let local = listReminder()
        var theirs = local
        theirs.title = "Продукты на неделю"
        theirs.markDone(through: day(2), at: day(2))
        theirs.updatedAt = day(2)
        let outcome = merge(local, with: try withoutNewFields(theirs), at: SyncStamp.of(theirs.updatedAt))
        let merged = try #require(outcome.snapshot.reminders.first)
        #expect(merged.title == "Продукты на неделю")
        #expect(merged.items.map(\.text) == ["Хлеб", "Молоко"])
        #expect(merged.items.allSatisfy { !$0.done })
        #expect(merged.contact == local.contact)
        #expect(!merged.doneWhenChecked)
        #expect(merged.history.map(\.occurrence) == [day(1), day(2)])
        #expect(SyncPlan.changes(in: outcome.snapshot, state: outcome.state).map(\.clientId) == [local.id.uuidString])
    }

    @Test func olderBuildCannotOverwriteARuleItDoesNotKnow() throws {
        var local = listReminder()
        local.schedule?.rule = .lastWorkday
        var theirs = local
        theirs.schedule?.rule = .monthlyOnDay(21)
        theirs.updatedAt = day(3)
        let outcome = merge(local, with: try withoutNewFields(theirs), at: SyncStamp.of(theirs.updatedAt))
        #expect(outcome.snapshot.reminders.first?.schedule?.rule == .lastWorkday)
    }

    @Test func ticksFromBothPhonesStay() throws {
        let base = listReminder()
        var local = base
        local.markDone(through: day(2), at: day(2))
        var theirs = base
        theirs.completedThrough = day(2)
        theirs.title = "Продукты, магазин у дома"
        theirs.updatedAt = day(3)
        let outcome = merge(local, with: try JSONValue(encoding: theirs), at: SyncStamp.of(theirs.updatedAt))
        let merged = try #require(outcome.snapshot.reminders.first)
        #expect(merged.title == "Продукты, магазин у дома")
        #expect(merged.history.map(\.occurrence) == [day(1), day(2)])
    }

    @Test func aTickTakenBackElsewhereDoesNotReturn() throws {
        var local = listReminder()
        local.markDone(through: day(2), at: day(2))
        var theirs = local
        theirs.reopen(before: day(2))
        theirs.updatedAt = day(3)
        let outcome = merge(local, with: try JSONValue(encoding: theirs), at: SyncStamp.of(theirs.updatedAt))
        let merged = try #require(outcome.snapshot.reminders.first)
        #expect(merged.history.map(\.occurrence) == [day(1)])
        #expect(merged == theirs)
        #expect(SyncPlan.changes(in: outcome.snapshot, state: outcome.state).isEmpty)
    }

    @Test func entriesThisBuildCannotReadAreWrittenBack() throws {
        let readable = listReminder()
        guard case .object(var fields) = try JSONValue(encoding: readable) else { return }
        fields["id"] = .string(UUID().uuidString)
        fields["schedule"] = .object(["start": .object(["year": .int(2026), "month": .int(10), "day": .int(1)]), "time": .object(["hour": .int(9), "minute": .int(0)]), "rule": .object(["fortnightly": .object([:])]), "end": .object(["never": .object([:])])])
        let file = JSONValue.object([
            "reminders": .array([try JSONValue(encoding: readable), .object(fields)]),
            "places": .array([]),
            "settings": try JSONValue(encoding: Settings.standard(at: created)),
        ])
        let data = try JSONEncoder().encode(file)
        let snapshot = try JSONDecoder().decode(StoreSnapshot.self, from: data)
        #expect(snapshot.reminders == [readable])
        #expect(!snapshot.unreadable.isEmpty)
        let written = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(snapshot))
        guard case .object(let back) = written, case .array(let reminders) = back["reminders"] else {
            Issue.record("no reminders")
            return
        }
        #expect(reminders.count == 2)
        #expect(reminders.contains(.object(fields)))
    }

    @Test func aFileNothingCanReadIsPutAside() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{\"reminders\": [".utf8).write(to: directory.appendingPathComponent(SharedStore.fileName))
        #expect(SharedStore.load(from: directory) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [SharedStore.fileName])
        #expect(SharedStore.load(from: directory, aside: true) == nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.contains { $0.hasPrefix("store-unreadable-") })
        #expect(!names.contains(SharedStore.fileName))
    }

    @Test func aPhoneNumberNeverLeavesThePhone() throws {
        let local = listReminder()
        let changes = SyncPlan.changes(in: StoreSnapshot(reminders: [local], places: [], settings: .standard(at: created), sounds: nil), state: SyncState())
        let data = try #require(changes.first { $0.kind == .reminders }?.data)
        guard case .object(let fields) = data else {
            Issue.record("not an object")
            return
        }
        #expect(fields["contact"] == nil)
        let outcome = merge(local, with: data, at: SyncStamp.of(local.updatedAt))
        #expect(outcome.snapshot.reminders.first?.contact == local.contact)
        #expect(SyncPlan.changes(in: outcome.snapshot, state: outcome.state).isEmpty)
    }

    @Test func skippingLeavesNoTick() {
        var reminder = listReminder()
        reminder.skip(through: day(2))
        #expect(reminder.completedThrough == day(2))
        #expect(reminder.history.map(\.occurrence) == [day(1)])
        #expect(reminder.items.allSatisfy { !$0.done })
    }

    @Test func aHeavyReminderIsTrimmedToWhatTheServerTakes() throws {
        var reminder = listReminder()
        let family = String(repeating: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}", count: 120)
        reminder.items = (0..<40).map { _ in ChecklistItem(text: family) }
        #expect(reminder.items[0].text.utf8.count <= ChecklistItem.maximumBytes)
        for index in 2..<100 {
            reminder.markDone(through: day(index), at: day(index))
        }
        reminder.fit()
        #expect(try JSONEncoder().encode(reminder).count <= Reminder.maximumBytes)
        #expect(reminder.items.count == 40)
        #expect(reminder.history.last?.occurrence == day(99))
    }

    @Test func aStreakOlderThanTheWindowSaysSo() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = day(200).addingTimeInterval(3_600 * 3)
        var old = listReminder()
        old.history = []
        var fresh = old
        fresh.id = UUID()
        fresh.schedule?.start = LocalDate(year: 2027, month: 2, day: 1)
        for reminder in [old, fresh] {
            var marked = reminder
            for occurrence in Recurrence.next(reminder.schedule!, after: now.addingTimeInterval(-99 * 86_400), limit: 120, calendar: calendar) where occurrence <= now {
                marked.markDone(through: occurrence, at: occurrence)
            }
            let streak = try #require(History.streaks([marked], now: now, calendar: calendar).first)
            #expect(streak.longer == (reminder.id == old.id))
        }
    }
}
