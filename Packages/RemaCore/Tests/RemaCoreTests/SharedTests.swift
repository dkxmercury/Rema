import Foundation
import Testing
@testable import RemaCore

struct SharedTests {
    let now = Date(timeIntervalSince1970: 1_791_300_000)

    func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    func item(_ json: String) throws -> SharedItem {
        try JSONDecoder().decode(SharedItem.self, from: Data(json.utf8))
    }

    let movieID = "0F8FAD5B-D9CB-469F-A165-70867728950E"

    func movieJSON(status: String = "accepted", doneMode: String = "each", myDone: Int64 = 0, doneThrough: Int64 = 0) -> String {
        """
        {"id": "\(movieID)", "gone": false, "owner": {"id": "anya", "name": "Аня"},
         "data": {"title": "Кино «Дюна»", "doneMode": "\(doneMode)",
                  "schedule": {"start": {"year": 2026, "month": 10, "day": 10}, "time": {"hour": 19, "minute": 0}, "end": {"never": {}}, "timeZone": "Asia/Tashkent"}},
         "clientUpdatedAt": 1000, "doneThrough": \(doneThrough), "myDone": \(myDone), "myStatus": "\(status)",
         "members": [{"id": "ilya", "name": "Илья", "status": "accepted", "doneThrough": 0}, {"id": "mama", "name": null, "status": "invited"}],
         "seq": 7}
        """
    }

    @Test func oneMomentForEverybodyInTheZoneOfTheCreator() throws {
        let schedule = Schedule(start: LocalDate(year: 2026, month: 10, day: 10), time: LocalTime(hour: 19, minute: 0), timeZone: "Asia/Tashkent")
        let moscow = calendar("Europe/Moscow")
        let ring = try #require(Recurrence.next(schedule, after: now, limit: 1, calendar: moscow).first)
        let parts = moscow.dateComponents([.day, .hour, .minute], from: ring)
        #expect(parts.day == 10 && parts.hour == 17 && parts.minute == 0)
        var local = schedule
        local.timeZone = nil
        let floating = try #require(Recurrence.next(local, after: now, limit: 1, calendar: moscow).first)
        #expect(moscow.component(.hour, from: floating) == 19)
    }

    @Test func serverAnswersAreReadEvenWithNulls() throws {
        let read = try item(movieJSON())
        #expect(read.owner?.name == "Аня")
        #expect(read.data?.schedule?.timeZone == "Asia/Tashkent")
        #expect(read.members.map(\.name) == ["Илья", ""])
        let gone = try item(#"{"id": "\#(movieID)", "gone": true, "owner": null, "data": null, "members": null, "seq": 9}"#)
        #expect(gone.gone && gone.members.isEmpty)
    }

    @Test func anInvitationNeitherRingsNorFillsTheDay() throws {
        let merged = SharedMerge.apply([try item(movieJSON(status: "invited"))], to: [], waiting: [], now: now)
        let invited = try #require(merged.first)
        #expect(invited.shared?.isInvitation == true)
        #expect(!invited.isLive)
        #expect(Scheduler.plan(reminders: merged, settings: .standard(at: now), now: now, calendar: calendar("Asia/Tashkent")).isEmpty)
        let accepted = SharedMerge.apply([try item(movieJSON())], to: merged, waiting: [], now: now)
        #expect(accepted.count == 1 && accepted[0].isLive)
    }

    @Test func whatEachPersonKeepsSurvivesAChange() throws {
        var local = try #require(SharedMerge.apply([try item(movieJSON())], to: [], waiting: [], now: now).first)
        local.preAlerts = [30]
        local.nag = true
        local.sound = .builtIn("gong")
        local.items = [ChecklistItem(text: "Билеты")]
        let changed = movieJSON().replacingOccurrences(of: "Кино «Дюна»", with: "Кино «Дюна», 2 часть")
        let merged = try #require(SharedMerge.apply([try item(changed)], to: [local], waiting: [], now: now).first)
        #expect(merged.title == "Кино «Дюна», 2 часть")
        #expect(merged.preAlerts == [30] && merged.nag && merged.sound == .builtIn("gong"))
        #expect(merged.items.map(\.text) == ["Билеты"])
    }

    @Test func ticksComeFromTheRightPlace() throws {
        let tick: Int64 = 1_791_400_000_000
        let own = try #require(SharedMerge.apply([try item(movieJSON(myDone: tick, doneThrough: 5))], to: [], waiting: [], now: now).first)
        #expect(own.completedThrough == Date(timeIntervalSince1970: Double(tick) / 1000))
        let single = try #require(SharedMerge.apply([try item(movieJSON(doneMode: "one", myDone: 0, doneThrough: tick))], to: [], waiting: [], now: now).first)
        #expect(single.completedThrough == Date(timeIntervalSince1970: Double(tick) / 1000))
        let reopened = try #require(SharedMerge.apply([try item(movieJSON(doneMode: "one", doneThrough: 0))], to: [single], waiting: [], now: now).first)
        #expect(reopened.completedThrough == nil)
    }

    @Test func goneAndWaitingReminders() throws {
        let merged = SharedMerge.apply([try item(movieJSON())], to: [], waiting: [], now: now)
        let id = try #require(merged.first?.id)
        let gone = try item(#"{"id": "\#(movieID)", "gone": true, "seq": 9}"#)
        #expect(SharedMerge.apply([gone], to: merged, waiting: [id], now: now).count == 1)
        #expect(SharedMerge.apply([gone], to: merged, waiting: [], now: now).isEmpty)
        let personal = Reminder(id: id, title: "Своё", schedule: nil, createdAt: now)
        #expect(SharedMerge.apply([gone], to: [personal], waiting: [], now: now).count == 1)
    }

    @Test func sharedRemindersStayOutOfThePersonalSync() throws {
        let shared = try #require(SharedMerge.apply([try item(movieJSON())], to: [], waiting: [], now: now).first)
        let own = Reminder(title: "Позвонить маме", schedule: nil, createdAt: now)
        let snapshot = StoreSnapshot(reminders: [shared, own], places: [], settings: .standard(at: now), sounds: nil)
        #expect(SyncPlan.changes(in: snapshot, state: SyncState()).map(\.clientId) == [own.id.uuidString])
    }

    @Test func aLatePushDoesNotUndoANewerState() throws {
        let fresh = movieJSON().replacingOccurrences(of: "\"seq\": 7", with: "\"seq\": 9").replacingOccurrences(of: "Кино «Дюна»", with: "Кино в 20:00")
        let merged = SharedMerge.apply([try item(fresh)], to: [], waiting: [], now: now)
        let late = try #require(SharedPush(userInfo: ["rema": ["event": "changed", "to": "ilya", "actor": "anya", "item": try JSONSerialization.jsonObject(with: Data(movieJSON().utf8))]])?.item)
        #expect(SharedMerge.apply([late], to: merged, waiting: [], now: now).first?.title == "Кино в 20:00")
        let gone = try #require(SharedPush(userInfo: ["rema": ["event": "deleted", "to": "ilya", "actor": "anya", "item": ["id": movieID, "gone": true, "seq": 8]]])?.item)
        #expect(SharedMerge.apply([gone], to: merged, waiting: [], now: now).count == 1)
        let later = try #require(SharedPush(userInfo: ["rema": ["event": "deleted", "to": "ilya", "actor": "anya", "item": ["id": movieID, "gone": true, "seq": 10]]])?.item)
        #expect(SharedMerge.apply([later], to: merged, waiting: [], now: now).isEmpty)
    }

    @Test func aPushWithoutParticipantsKeepsTheKnownOnes() throws {
        let merged = SharedMerge.apply([try item(movieJSON())], to: [], waiting: [], now: now)
        var partial = try JSONSerialization.jsonObject(with: Data(movieJSON().replacingOccurrences(of: "\"seq\": 7", with: "\"seq\": 8").utf8)) as! [String: Any]
        partial["members"] = nil
        partial["partial"] = true
        let push = try #require(SharedPush(userInfo: ["rema": ["event": "changed", "to": "ilya", "actor": "anya", "item": partial]]))
        #expect(push.event == .changed && push.recipient == "ilya")
        let pushed = try #require(push.item)
        let after = try #require(SharedMerge.apply([pushed], to: merged, waiting: [], now: now).first)
        #expect(after.shared?.members.map(\.id) == ["ilya", "mama"])
        #expect(after.shared?.seq == 8)
        #expect(SharedPush(userInfo: ["aps": ["alert": "hi"]]) == nil)
    }

    @Test func aTickNotConfirmedYetOnlyMovesForward() throws {
        let tick: Int64 = 1_791_400_000_000
        var local = try #require(SharedMerge.apply([try item(movieJSON())], to: [], waiting: [], now: now).first)
        local.markDone(through: Date(timeIntervalSince1970: Double(tick) / 1000), at: now)
        let unconfirmed = SharedMerge.unconfirmed([local], acknowledged: [movieID: 0])
        #expect(unconfirmed == [local.id])
        #expect(SharedMerge.unconfirmed([local], acknowledged: [movieID: tick]).isEmpty)
        #expect(SharedMerge.unconfirmed([local], acknowledged: [:]).isEmpty)
        let renamed = movieJSON().replacingOccurrences(of: "Кино «Дюна»", with: "Кино в 20:00").replacingOccurrences(of: "\"seq\": 7", with: "\"seq\": 8")
        let kept = try #require(SharedMerge.apply([try item(renamed)], to: [local], waiting: [], unconfirmed: unconfirmed, now: now).first)
        #expect(kept.title == "Кино в 20:00")
        #expect(kept.completedThrough == local.completedThrough)
        let undone = try #require(SharedMerge.apply([try item(renamed)], to: [local], waiting: [], now: now).first)
        #expect(undone.completedThrough == nil)
        let later = try #require(SharedMerge.apply([try item(movieJSON(myDone: tick + 86_400_000).replacingOccurrences(of: "\"seq\": 7", with: "\"seq\": 9"))], to: [local], waiting: [], unconfirmed: unconfirmed, now: now).first)
        #expect(later.completedThrough == Date(timeIntervalSince1970: Double(tick + 86_400_000) / 1000))
    }

    @Test func onlyItemsTakenInAreReported() throws {
        let fresh = movieJSON().replacingOccurrences(of: "\"seq\": 7", with: "\"seq\": 9")
        let merged = SharedMerge.apply([try item(fresh)], to: [], waiting: [], now: now)
        var reported: [Int64] = []
        _ = SharedMerge.apply([try item(movieJSON()), try item(fresh)], to: merged, waiting: [], now: now) { reported.append($0.seq) }
        #expect(reported == [9])
        let id = try #require(merged.first?.id)
        _ = SharedMerge.apply([try item(fresh)], to: merged, waiting: [id], now: now) { reported.append($0.seq) }
        #expect(reported == [9])
    }

    @Test func pushesWaitInTheInboxInTheOrderTheyCame() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(SharedInbox.items(in: folder).isEmpty)
        let renamed = movieJSON().replacingOccurrences(of: "Кино «Дюна»", with: "Кино в 20:00").replacingOccurrences(of: "\"seq\": 7", with: "\"seq\": 8")
        try SharedInbox.add(try item(movieJSON()), in: folder, now: now)
        try SharedInbox.add(try item(renamed), in: folder, now: now.addingTimeInterval(5))
        #expect(SharedInbox.items(in: folder).map(\.seq) == [7, 8])
        let taken = SharedInbox.take(from: folder)
        #expect(taken.map(\.seq) == [7, 8])
        #expect(taken.last?.data?.title == "Кино в 20:00")
        #expect(SharedMerge.apply(taken, to: [], waiting: [], now: now).first?.title == "Кино в 20:00")
        #expect(SharedInbox.take(from: folder).isEmpty)
        try SharedInbox.add(try item(movieJSON()), in: folder, now: now)
        SharedInbox.clear(in: folder)
        #expect(SharedInbox.items(in: folder).isEmpty)
    }

    @Test func aReminderFromAnOlderBuildStaysShared() throws {
        let saved = #"{"owner": {"id": "anya", "name": "Аня"}, "status": "accepted", "members": [], "doneMode": "one"}"#
        let info = try JSONDecoder().decode(SharedInfo.self, from: Data(saved.utf8))
        #expect(info.doneMode == .one && info.seq == 0 && !info.pending)
    }

    @Test func theSharedPartIsTitleTimeAndDoneMode() throws {
        let shared = try #require(SharedMerge.apply([try item(movieJSON(doneMode: "one"))], to: [], waiting: [], now: now).first)
        let data = try JSONValue(encoding: shared.sharedData)
        guard case .object(let fields) = data else {
            Issue.record("not an object")
            return
        }
        #expect(Set(fields.keys) == ["title", "schedule", "doneMode"])
        #expect(shared.sharedData.doneMode == .one)
    }
}
