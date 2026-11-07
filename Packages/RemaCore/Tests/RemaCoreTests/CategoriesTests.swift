import Foundation
import Testing
@testable import RemaCore

struct CategoriesTests {
    let created = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func categoriesAreAddedRenamedMovedAndRemoved() throws {
        var settings = Settings.standard(at: created)
        #expect(settings.addCategory(named: "   ") == nil)
        let work = try #require(settings.addCategory(named: " Работа "))
        let home = try #require(settings.addCategory(named: "Дом"))
        let health = try #require(settings.addCategory(named: "Здоровье"))
        #expect(work.name == "Работа")
        #expect(Set([work.color, home.color, health.color]).count == 3)
        settings.renameCategory(home.id, to: "Дом и дача")
        #expect(settings.category(home.id)?.name == "Дом и дача")
        settings.renameCategory(home.id, to: "  ")
        #expect(settings.category(home.id)?.name == "Дом и дача")
        settings.moveCategories(from: IndexSet(integer: 2), to: 0)
        #expect(settings.categories?.map(\.name) == ["Здоровье", "Работа", "Дом и дача"])
        settings.moveCategories(from: IndexSet(integer: 0), to: 3)
        #expect(settings.categories?.map(\.name) == ["Работа", "Дом и дача", "Здоровье"])
        settings.removeCategory(work.id)
        settings.removeCategory(home.id)
        settings.removeCategory(health.id)
        #expect(settings.categories == [])
        #expect(settings.category(work.id) == nil)
    }

    @Test func thereIsALimitAndALongNameIsCut() {
        var settings = Settings.standard(at: created)
        for index in 0..<ReminderCategory.limit {
            #expect(settings.addCategory(named: "Категория \(index)") != nil)
        }
        #expect(settings.addCategory(named: "Ещё одна") == nil)
        var other = Settings.standard(at: created)
        let long = other.addCategory(named: String(repeating: "я", count: 50))
        #expect(long?.name.count == ReminderCategory.nameLimit)
    }

    @Test func reminderAlwaysWritesItsCategoryAndBirthday() throws {
        let plain = Reminder(title: "Позвонить", schedule: nil, createdAt: created)
        guard case .object(let fields) = try JSONValue(encoding: plain) else { Issue.record("not an object"); return }
        #expect(fields["category"] == .null)
        #expect(fields["birthday"] == .null)

        let category = UUID()
        let birthday = Reminder(title: "День рождения: Аня", schedule: nil, createdAt: created, category: category, birthday: BirthdayNote(name: "Аня", year: 1996))
        let decoded = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(birthday))
        #expect(decoded.category == category)
        #expect(decoded.birthday == BirthdayNote(name: "Аня", year: 1996))
        #expect(decoded.birthday?.age(on: LocalDate(year: 2026, month: 11, day: 12)) == 30)
    }

    @Test func dataFromAnOlderBuildDecodesWithoutThem() throws {
        let older = Reminder(title: "Купить хлеб", schedule: nil, createdAt: created)
        guard case .object(var fields) = try JSONValue(encoding: older) else { Issue.record("not an object"); return }
        fields["category"] = nil
        fields["birthday"] = nil
        let decoded = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(JSONValue.object(fields)))
        #expect(decoded.category == nil)
        #expect(decoded.birthday == nil)
        #expect(BirthdayNote(name: "Аня", year: 1700).year == nil)
    }

    @Test func anOlderBuildCannotWipeThemButANewerOneCanClearThem() throws {
        var local = Reminder(title: "Отчёт", schedule: nil, createdAt: created, category: UUID(), birthday: BirthdayNote(name: "Аня"))
        local.updatedAt = created
        var theirs = local
        theirs.title = "Отчёт за неделю"
        theirs.updatedAt = created.addingTimeInterval(60)
        guard case .object(var older) = try JSONValue(encoding: theirs) else { Issue.record("not an object"); return }
        older["category"] = nil
        older["birthday"] = nil
        let kept = try #require(merge(local, data: .object(older), at: theirs.updatedAt).snapshot.reminders.first)
        #expect(kept.title == "Отчёт за неделю")
        #expect(kept.category == local.category)
        #expect(kept.birthday == local.birthday)

        theirs.category = nil
        theirs.birthday = nil
        let cleared = try #require(merge(local, data: try JSONValue(encoding: theirs), at: theirs.updatedAt).snapshot.reminders.first)
        #expect(cleared.category == nil)
        #expect(cleared.birthday == nil)
    }

    @Test func settingsFromAnOlderBuildKeepTheCategories() throws {
        var local = Settings.standard(at: created)
        local.addCategory(named: "Работа")
        local.updatedAt = created
        var theirs = Settings.standard(at: created)
        theirs.morning = LocalTime(hour: 8, minute: 0)
        theirs.updatedAt = created.addingTimeInterval(60)
        guard case .object(var fields) = try JSONValue(encoding: theirs) else { Issue.record("not an object"); return }
        fields["categories"] = nil
        let key = SyncState.key(.prefs, SyncState.settingsID)
        let record = SyncRecord(kind: SyncKind.prefs.rawValue, clientId: SyncState.settingsID, data: .object(fields), clientUpdatedAt: SyncStamp.of(theirs.updatedAt), deleted: false, seq: 1)
        let snapshot = StoreSnapshot(reminders: [], places: [], settings: local, sounds: nil)
        let outcome = SyncMerge.apply(SyncResponse(records: [record], rejected: [], cursor: 1, more: false), sent: [], to: snapshot, state: SyncState(known: [key: SyncStamp.of(local.updatedAt)]), now: created)
        #expect(outcome.snapshot.settings.morning == LocalTime(hour: 8, minute: 0))
        #expect(outcome.snapshot.settings.categories?.map(\.name) == ["Работа"])
    }

    private func merge(_ local: Reminder, data: JSONValue, at stamp: Date) -> SyncMerge.Outcome {
        let key = SyncState.key(.reminders, local.id.uuidString)
        let state = SyncState(known: [key: SyncStamp.of(local.updatedAt)])
        let record = SyncRecord(kind: SyncKind.reminders.rawValue, clientId: local.id.uuidString, data: data, clientUpdatedAt: SyncStamp.of(stamp), deleted: false, seq: 1)
        let response = SyncResponse(records: [record], rejected: [], cursor: 1, more: false)
        let snapshot = StoreSnapshot(reminders: [local], places: [], settings: .standard(at: created), sounds: nil)
        return SyncMerge.apply(response, sent: [], to: snapshot, state: state, now: created)
    }
}
