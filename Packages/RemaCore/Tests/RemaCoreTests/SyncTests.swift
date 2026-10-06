import Foundation
import Testing
@testable import RemaCore

struct SyncTests {
    let created = Date(timeIntervalSince1970: 1_790_000_000.123)

    func reminder(_ title: String, at date: Date? = nil) -> Reminder {
        Reminder(
            title: title,
            schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 6), time: LocalTime(hour: 9, minute: 30), rule: .weekly([.monday, .friday]), end: .count(5)),
            preAlerts: [15, 1440],
            nag: true,
            urgent: true,
            sound: .custom(UUID()),
            createdAt: date ?? created
        )
    }

    func snapshot(reminders: [Reminder] = [], places: [Place] = [], sounds: [CustomSound] = [], settings: Settings? = nil) -> StoreSnapshot {
        StoreSnapshot(reminders: reminders, places: places, settings: settings ?? .standard(at: created), sounds: sounds)
    }

    func record(_ kind: SyncKind, _ id: String, _ data: JSONValue?, at stamp: Int64, deleted: Bool = false, file: String? = nil, seq: Int64 = 1) -> SyncRecord {
        SyncRecord(kind: kind.rawValue, clientId: id, data: data, clientUpdatedAt: stamp, deleted: deleted, file: file, seq: seq)
    }

    func respond(_ records: [SyncRecord], rejected: [SyncRejection] = [], cursor: Int64 = 1) -> SyncResponse {
        SyncResponse(records: records, rejected: rejected, cursor: cursor, more: false)
    }

    @Test func modelsSurviveTheTripThroughJSON() throws {
        let call = reminder("Позвонить маме")
        #expect(try JSONValue(encoding: call).decode(Reminder.self) == call)
        let gym = Place(name: "Зал", icon: "sport", latitude: 41.311081, longitude: 69.240562, radius: 300, createdAt: created, remembered: false)
        #expect(try JSONValue(encoding: gym).decode(Place.self) == gym)
        var settings = Settings.standard(at: created)
        settings.nagInterval = 10
        settings.morning = LocalTime(hour: 7, minute: 45)
        #expect(try JSONValue(encoding: settings).decode(Settings.self) == settings)
        let text = String(decoding: try JSONEncoder().encode(JSONValue(encoding: call)), as: UTF8.self)
        #expect(text.contains("\"title\":\"Позвонить маме\""))
    }

    @Test func freshDefaultsAreNotPushed() {
        let plan = SyncPlan.changes(in: snapshot(), state: SyncState())
        #expect(plan.isEmpty)
        var settings = Settings.standard(at: created)
        settings.appearance = .dark
        let changed = SyncPlan.changes(in: snapshot(settings: settings), state: SyncState())
        #expect(changed.map(\.kind) == [.prefs])
        #expect(changed.first?.clientId == SyncState.settingsID)
    }

    @Test func everythingLocalIsPushedOnceThenNothing() {
        let call = reminder("Позвонить")
        var gone = reminder("Старое")
        gone.deletedAt = created
        let home = Place(name: "Дом", icon: "home", latitude: 41.3, longitude: 69.2, radius: 200, createdAt: created)
        let gong = CustomSound(name: "gong.mp3", duration: 12, createdAt: created)
        let local = snapshot(reminders: [call, gone], places: [home], sounds: [gong])

        let plan = SyncPlan.changes(in: local, state: SyncState())
        #expect(plan.count == 4)
        let deleted = plan.first { $0.clientId == gone.id.uuidString }
        #expect(deleted?.deleted == true && deleted?.data == nil)
        #expect(plan.first { $0.clientId == call.id.uuidString }?.clientUpdatedAt == SyncStamp.of(call.updatedAt))

        let outcome = SyncMerge.apply(respond([]), sent: plan, to: local, state: SyncState(), now: created)
        #expect(SyncPlan.changes(in: outcome.snapshot, state: outcome.state).isEmpty)
        #expect(!outcome.snapshot.reminders.contains { $0.id == gone.id }, "an acknowledged deletion is not kept locally")
        #expect(outcome.snapshot.reminders.contains { $0.id == call.id })
        #expect(SyncPlan.changes(in: local, state: SyncState(), limit: 2).count == 2)
    }

    @Test func newerServerVersionReplacesLocal() throws {
        let call = reminder("Позвонить")
        var edited = call
        edited.title = "Позвонить папе"
        edited.updatedAt = created.addingTimeInterval(60)
        let state = SyncState(known: [SyncState.key(.reminders, call.id.uuidString): SyncStamp.of(call.updatedAt)])
        let response = respond([record(.reminders, call.id.uuidString, try JSONValue(encoding: edited), at: SyncStamp.of(edited.updatedAt))])

        let outcome = SyncMerge.apply(response, sent: [], to: snapshot(reminders: [call]), state: state, now: created)
        #expect(outcome.changed)
        #expect(outcome.snapshot.reminders == [edited])
        #expect(SyncPlan.changes(in: outcome.snapshot, state: outcome.state).isEmpty)
    }

    @Test func newerLocalVersionWinsAndStaysToPush() throws {
        let call = reminder("Позвонить")
        var mine = call
        mine.title = "Моё"
        mine.updatedAt = created.addingTimeInterval(120)
        var theirs = call
        theirs.title = "Чужое"
        theirs.updatedAt = created.addingTimeInterval(60)
        let response = respond([record(.reminders, call.id.uuidString, try JSONValue(encoding: theirs), at: SyncStamp.of(theirs.updatedAt))])

        let outcome = SyncMerge.apply(response, sent: [], to: snapshot(reminders: [mine]), state: SyncState(), now: created)
        #expect(!outcome.changed)
        #expect(outcome.snapshot.reminders == [mine])
        #expect(SyncPlan.changes(in: outcome.snapshot, state: outcome.state).map(\.clientId) == [call.id.uuidString])
    }

    @Test func ownEchoChangesNothing() throws {
        let call = reminder("Позвонить")
        let sent = SyncPlan.changes(in: snapshot(reminders: [call]), state: SyncState())
        let response = respond([record(.reminders, call.id.uuidString, try JSONValue(encoding: call), at: SyncStamp.of(call.updatedAt))])
        let outcome = SyncMerge.apply(response, sent: sent, to: snapshot(reminders: [call]), state: SyncState(), now: created)
        #expect(!outcome.changed)
        #expect(outcome.snapshot.reminders == [call])
    }

    @Test func remoteDeletionRemovesLocalUnlessEditedLater() throws {
        let call = reminder("Позвонить")
        let key = SyncState.key(.reminders, call.id.uuidString)
        let deletion = record(.reminders, call.id.uuidString, nil, at: SyncStamp.of(call.updatedAt) + 1000, deleted: true)
        let outcome = SyncMerge.apply(respond([deletion]), sent: [], to: snapshot(reminders: [call]), state: SyncState(known: [key: SyncStamp.of(call.updatedAt)]), now: created)
        #expect(outcome.changed && outcome.snapshot.reminders.isEmpty)
        #expect(outcome.state.known[key] == nil)

        var edited = call
        edited.updatedAt = created.addingTimeInterval(10)
        let early = record(.reminders, call.id.uuidString, nil, at: SyncStamp.of(call.updatedAt) + 1, deleted: true)
        let kept = SyncMerge.apply(respond([early]), sent: [], to: snapshot(reminders: [edited]), state: SyncState(), now: created)
        #expect(kept.snapshot.reminders == [edited])
        #expect(SyncPlan.changes(in: kept.snapshot, state: kept.state).count == 1, "the later edit brings it back on the server")
    }

    @Test func newRecordsArriveAndBrokenOnesAreSkipped() throws {
        let call = reminder("С другого телефона")
        let response = respond([
            record(.reminders, call.id.uuidString, try JSONValue(encoding: call), at: SyncStamp.of(call.updatedAt)),
            record(.reminders, UUID().uuidString, .object(["title": .string("без полей")]), at: 5),
            record(.reminders, "not-a-uuid", .null, at: 5),
            record(.places, UUID().uuidString, nil, at: 5, deleted: true),
            SyncRecord(kind: "future", clientId: "x", data: nil, clientUpdatedAt: 1, deleted: false, seq: 9),
        ], cursor: 9)
        let outcome = SyncMerge.apply(response, sent: [], to: snapshot(), state: SyncState(), now: created)
        #expect(outcome.snapshot.reminders == [call])
        #expect(outcome.state.cursor == 9)
        #expect(outcome.state.lastSync == created)
    }

    @Test func untouchedSettingsTakeTheAccountOnes() throws {
        var account = Settings.standard(at: created.addingTimeInterval(-86_400))
        account.evening = LocalTime(hour: 21, minute: 0)
        let fresh = Settings.standard(at: created)
        let response = respond([record(.prefs, SyncState.settingsID, try JSONValue(encoding: account), at: SyncStamp.of(account.updatedAt))])
        let outcome = SyncMerge.apply(response, sent: [], to: snapshot(settings: fresh), state: SyncState(), now: created)
        #expect(outcome.snapshot.settings == account)

        var mine = Settings.standard(at: created)
        mine.evening = LocalTime(hour: 18, minute: 0)
        let kept = SyncMerge.apply(response, sent: [], to: snapshot(settings: mine), state: SyncState(), now: created)
        #expect(kept.snapshot.settings == mine)
        #expect(SyncPlan.changes(in: kept.snapshot, state: kept.state).map(\.kind) == [.prefs])
    }

    @Test func rejectedChangesAreNotRetriedForever() {
        var gone = reminder("Удалено")
        gone.deletedAt = created
        let call = reminder("Слишком длинно")
        let local = snapshot(reminders: [call, gone])
        let sent = SyncPlan.changes(in: local, state: SyncState())
        let rejected = sent.map { SyncRejection(kind: $0.kind.rawValue, clientId: $0.clientId, reason: "limit") }
        let outcome = SyncMerge.apply(respond([], rejected: rejected), sent: sent, to: local, state: SyncState(), now: created)
        #expect(SyncPlan.changes(in: outcome.snapshot, state: outcome.state).isEmpty)
        #expect(outcome.snapshot.reminders.count == 2, "a rejected deletion stays until the server takes it")
        #expect(outcome.rejected.count == 2)
    }

    @Test func soundFilesAreReported() throws {
        let gong = CustomSound(name: "gong", duration: 3, createdAt: created)
        let response = respond([record(.sounds, gong.id.uuidString, try JSONValue(encoding: gong), at: SyncStamp.of(gong.createdAt), file: "gong_x1.caf")])
        let outcome = SyncMerge.apply(response, sent: [], to: snapshot(), state: SyncState(), now: created)
        #expect(outcome.snapshot.sounds == [gong])
        #expect(outcome.soundFiles[gong.id] == "gong_x1.caf")
    }

    @Test func fullResyncDropsWhatTheServerForgot() {
        let synced = reminder("Было в аккаунте")
        let local = reminder("Только на телефоне")
        let state = SyncState(cursor: 40, lastSync: created, known: [SyncState.key(.reminders, synced.id.uuidString): SyncStamp.of(synced.updatedAt)])
        let outcome = SyncMerge.reconcile(snapshot(reminders: [synced, local]), state: state, seen: [])
        #expect(outcome.snapshot.reminders == [local])
        #expect(outcome.state.known.isEmpty)

        #expect(!state.needsFullResync(now: created.addingTimeInterval(30 * 86_400)))
        #expect(state.needsFullResync(now: created.addingTimeInterval(91 * 86_400)))
        #expect(!SyncState().needsFullResync(now: created))
    }

    @Test func requestEncodesDataAsObject() throws {
        let call = reminder("Позвонить")
        let request = SyncRequest(since: 3, changes: SyncPlan.changes(in: snapshot(reminders: [call]), state: SyncState()))
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        let change = try #require((json["changes"] as? [[String: Any]])?.first)
        #expect(change["kind"] as? String == "reminders")
        #expect((change["data"] as? [String: Any])?["title"] as? String == "Позвонить")
    }

    @Test func refusedRecordsSurviveAFullResync() {
        let call = reminder("Отклонено")
        let local = snapshot(reminders: [call])
        let sent = SyncPlan.changes(in: local, state: SyncState())
        let refused = sent.map { SyncRejection(kind: $0.kind.rawValue, clientId: $0.clientId, reason: "clock") }
        let outcome = SyncMerge.apply(respond([], rejected: refused), sent: sent, to: local, state: SyncState(), now: created)
        let full = SyncMerge.reconcile(outcome.snapshot, state: outcome.state, seen: [])
        #expect(full.snapshot.reminders == [call])
        var edited = call
        edited.title = "Исправлено"
        edited.updatedAt = created.addingTimeInterval(60)
        #expect(SyncPlan.changes(in: snapshot(reminders: [edited]), state: full.state).map(\.clientId) == [call.id.uuidString])
    }

    @Test func settingsPutBackToDefaultsStillSync() {
        var settings = Settings.standard(at: created.addingTimeInterval(60))
        settings.touched = true
        #expect(SyncPlan.changes(in: snapshot(settings: settings), state: SyncState()).map(\.kind) == [.prefs])
    }

    @Test func olderFilesStillDecode() throws {
        let state = try JSONDecoder().decode(SyncState.self, from: Data(#"{"cursor":3,"known":{"reminders/x":5}}"#.utf8))
        #expect(state.cursor == 3)
        #expect(state.held == nil)
        let settings = try JSONValue(encoding: Settings.standard(at: created)).decode(Settings.self)
        #expect(settings.touched == nil)
    }
}
