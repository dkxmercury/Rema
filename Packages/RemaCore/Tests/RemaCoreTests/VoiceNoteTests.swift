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

    @Test func theOwnerSendsTheNoteToTheFriends() throws {
        var movie = reminder("Кино")
        let note = CustomSound(name: "Кино", duration: 9.5, createdAt: created, reminderID: movie.id)
        movie.sound = .custom(note.id)
        #expect(movie.sharedData(sounds: [note]).voice == SharedVoice(id: note.id, duration: 9.5))
        guard case .object(let fields) = try JSONValue(encoding: movie.sharedData(sounds: [])) else {
            Issue.record("not an object")
            return
        }
        #expect(fields["voice"] == .null)
    }

    @Test func aFriendKeepsTheNoteOfTheReminder() throws {
        let json = """
        {"id": "0F8FAD5B-D9CB-469F-A165-70867728950E", "gone": false, "owner": {"id": "anya", "name": "Аня"},
         "data": {"title": "Кино", "doneMode": "each", "voice": {"id": "5C7E2A10-1B2C-4D3E-8F40-A1B2C3D4E5F6", "duration": 12}},
         "clientUpdatedAt": 1000, "doneThrough": 0, "myDone": 0, "myStatus": "accepted", "members": [], "seq": 7}
        """
        let item = try JSONDecoder().decode(SharedItem.self, from: Data(json.utf8))
        let friend = try #require(SharedMerge.apply([item], to: [], waiting: [], now: created).first)
        let voice = SharedVoice(id: try #require(UUID(uuidString: "5C7E2A10-1B2C-4D3E-8F40-A1B2C3D4E5F6")), duration: 12)
        #expect(friend.shared?.voice == voice)
        let saved = try JSONDecoder().decode(SharedInfo.self, from: JSONEncoder().encode(try #require(friend.shared)))
        #expect(saved.voice == voice)
    }

    @Test func aBrokenNoteFromTheServerIsLeftOut() throws {
        let data = try JSONDecoder().decode(SharedData.self, from: Data(#"{"title": "Кино", "doneMode": "each", "voice": {"id": "nope"}}"#.utf8))
        #expect(data.voice == nil)
        #expect(data.title == "Кино")
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
