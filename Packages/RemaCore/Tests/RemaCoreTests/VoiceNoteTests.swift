import Foundation
import Testing
@testable import RemaCore

struct VoiceNoteTests {
    let created = Date(timeIntervalSince1970: 1_790_000_000)

    func reminder(_ title: String) -> Reminder {
        Reminder(title: title, schedule: Schedule(start: LocalDate(year: 2026, month: 11, day: 9), time: LocalTime(hour: 21, minute: 0)), createdAt: created)
    }

    @Test func aNoteBelongsToItsReminder() {
        var bread = reminder("Купить хлеб")
        let note = CustomSound(name: "Купить хлеб", duration: 12, createdAt: created, reminderID: bread.id)
        bread.sound = .custom(note.id)
        #expect(bread.voiceNote(in: [note]) == note)
        #expect(note.isVoiceNote)

        var other = reminder("Позвонить маме")
        other.sound = .custom(note.id)
        #expect(other.voiceNote(in: [note]) == nil)

        var gone = note
        gone.deletedAt = created.addingTimeInterval(60)
        #expect(bread.voiceNote(in: [gone]) == nil)

        bread.sound = .standard
        #expect(bread.voiceNote(in: [note]) == nil)
    }

    @Test func anOlderBuildKeepsTheLink() throws {
        let owner = UUID()
        let note = CustomSound(name: "Купить хлеб", duration: 12, createdAt: created, reminderID: owner)
        var renamed = CustomSound(id: note.id, name: "Хлеб", duration: 12, createdAt: created)
        renamed.reminderID = nil
        let snapshot = StoreSnapshot(reminders: [], places: [], settings: .standard(at: created), sounds: [note])
        let record = SyncRecord(kind: SyncKind.sounds.rawValue, clientId: note.id.uuidString, data: try JSONValue(encoding: renamed), clientUpdatedAt: SyncStamp.of(renamed), deleted: false, seq: 1)
        let response = SyncResponse(records: [record], rejected: [], cursor: 1, more: false)
        let merged = SyncMerge.apply(response, sent: [], to: snapshot, state: SyncState(), now: created).snapshot.sounds ?? []
        #expect(merged.first?.name == "Хлеб")
        #expect(merged.first?.reminderID == owner)
    }

    @Test func aNoteArrivesWithItsLink() throws {
        let owner = UUID()
        let note = CustomSound(name: "Купить хлеб", duration: 12, createdAt: created, reminderID: owner)
        let snapshot = StoreSnapshot(reminders: [], places: [], settings: .standard(at: created), sounds: [])
        let record = SyncRecord(kind: SyncKind.sounds.rawValue, clientId: note.id.uuidString, data: try JSONValue(encoding: note), clientUpdatedAt: SyncStamp.of(note), deleted: false, seq: 1)
        let response = SyncResponse(records: [record], rejected: [], cursor: 1, more: false)
        let merged = SyncMerge.apply(response, sent: [], to: snapshot, state: SyncState(), now: created).snapshot.sounds ?? []
        #expect(merged == [note])
    }
}
