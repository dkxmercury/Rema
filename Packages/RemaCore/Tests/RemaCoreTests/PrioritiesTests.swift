import Foundation
import Testing
@testable import RemaCore

struct PrioritiesTests {
    let created = Date(timeIntervalSince1970: 1_790_000_000)
    let today = LocalDate(year: 2026, month: 11, day: 5)

    func merged(local: Settings, incoming: Settings) throws -> Settings {
        let snapshot = StoreSnapshot(reminders: [], places: [], settings: local, sounds: [])
        let record = SyncRecord(kind: SyncKind.prefs.rawValue, clientId: SyncState.settingsID, data: try JSONValue(encoding: incoming), clientUpdatedAt: SyncStamp.of(incoming.updatedAt), deleted: false, seq: 1)
        let response = SyncResponse(records: [record], rejected: [], cursor: 1, more: false)
        return SyncMerge.apply(response, sent: [], to: snapshot, state: SyncState(), now: created).snapshot.settings
    }

    @Test func picksBelongToTheirDay() {
        let ids = (0..<5).map { _ in UUID() }
        var settings = Settings.standard(at: created)
        settings.priorities = Priorities(day: today, ids: ids)
        #expect(settings.priorityIDs(on: today) == Array(ids.prefix(3)))
        #expect(settings.priorityIDs(on: today.adding(days: 1)).isEmpty)
    }

    @Test func anOlderBuildKeepsThePicks() throws {
        var local = Settings.standard(at: created)
        local.touched = true
        local.priorities = Priorities(day: today, ids: [UUID()])
        var incoming = Settings.standard(at: created.addingTimeInterval(60))
        incoming.touched = true
        incoming.nagInterval = 10
        let result = try merged(local: local, incoming: incoming)
        #expect(result.nagInterval == 10)
        #expect(result.priorities == local.priorities)
    }

    @Test func aNewerBuildReplacesThePicks() throws {
        var local = Settings.standard(at: created)
        local.touched = true
        local.priorities = Priorities(day: today, ids: [UUID()])
        var incoming = Settings.standard(at: created.addingTimeInterval(60))
        incoming.touched = true
        incoming.priorities = Priorities(day: today, ids: [])
        #expect(try merged(local: local, incoming: incoming).priorities == Priorities(day: today, ids: []))
    }
}
