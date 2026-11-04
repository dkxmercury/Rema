import Foundation
import Testing
@testable import RemaCore

struct PillCountTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        return calendar
    }()

    func moment(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    var now: Date {
        moment(9, 13, 50)
    }

    func daily(_ title: String = "Пить таблетки", hour: Int, until: LocalDate? = nil) -> Reminder {
        let end: RepeatEnd = until.map { .until($0) } ?? .never
        return Reminder(title: title, schedule: Schedule(start: LocalDate(year: 2026, month: 11, day: 1), time: LocalTime(hour: hour, minute: 0), rule: .daily, end: end), createdAt: moment(1, 8))
    }

    func course(_ reminders: [Reminder], left: Int, counted: Date? = nil, perDose: Int = 1) -> PillCourse {
        PillCourse(reminderIDs: reminders.map(\.id), left: left, counted: counted ?? moment(9, 10), perDose: perDose, warnDays: 3)
    }

    @Test func ticksAfterTheCountTakePills() {
        var morning = daily(hour: 9)
        var evening = daily(hour: 21)
        morning.markDone(through: moment(8, 9), at: moment(8, 9, 5))
        evening.markDone(through: moment(8, 21), at: moment(8, 21, 1))
        morning.markDone(through: moment(9, 9), at: moment(9, 9, 2))
        let box = course([morning, evening], left: 10, counted: moment(8, 12))
        #expect(PillCount.left(box, reminders: [morning, evening]) == 8)
    }

    @Test func aSkippedDoseTakesNoPill() {
        var morning = daily(hour: 9)
        morning.skip(through: moment(9, 9))
        let box = course([morning], left: 5, counted: moment(9, 8))
        #expect(PillCount.left(box, reminders: [morning]) == 5)
    }

    @Test func fewPillsLeftAreLow() {
        var morning = daily(hour: 9)
        let evening = daily(hour: 21)
        morning.markDone(through: moment(9, 9), at: moment(9, 9, 2))
        let forecast = PillCount.forecast(course([morning, evening], left: 5), reminders: [morning, evening], now: now, calendar: calendar)
        #expect(forecast.pills == 5)
        #expect(forecast.lastDose == moment(11, 21))
        #expect(forecast.days == 3)
        #expect(forecast.low)
    }

    @Test func plentyIsNotLow() {
        let morning = daily(hour: 9)
        let evening = daily(hour: 21)
        let forecast = PillCount.forecast(course([morning, evening], left: 20), reminders: [morning, evening], now: now, calendar: calendar)
        #expect(forecast.low == false)
        #expect(forecast.days == 10)
    }

    @Test func aDoseNotTickedTodayIsStillToTake() {
        let morning = daily(hour: 9)
        let evening = daily(hour: 21)
        let forecast = PillCount.forecast(course([morning, evening], left: 2), reminders: [morning, evening], now: now, calendar: calendar)
        #expect(forecast.lastDose == moment(9, 21))
        #expect(forecast.days == 1)
    }

    @Test func pillsToTheEndOfTheCourseAreEnough() {
        let last = LocalDate(year: 2026, month: 11, day: 10)
        let morning = daily(hour: 9, until: last)
        let evening = daily(hour: 21, until: last)
        let forecast = PillCount.forecast(course([morning, evening], left: 5), reminders: [morning, evening], now: now, calendar: calendar)
        #expect(forecast.days == 2)
        #expect(forecast.low == false)
    }

    @Test func aLaterMomentCountsTheDosesBeforeIt() {
        let morning = daily(hour: 9)
        let evening = daily(hour: 21)
        let forecast = PillCount.forecast(course([morning, evening], left: 5), reminders: [morning, evening], at: moment(10, 21), now: now, calendar: calendar)
        #expect(forecast.pills == 3)
        #expect(forecast.lastDose == moment(11, 21))
        #expect(forecast.days == 2)
        #expect(forecast.low)
    }

    @Test func twoPillsAtATime() {
        var morning = daily(hour: 9)
        let evening = daily(hour: 21)
        morning.markDone(through: moment(9, 9), at: moment(9, 9, 2))
        let forecast = PillCount.forecast(course([morning, evening], left: 5, perDose: 2), reminders: [morning, evening], now: now, calendar: calendar)
        #expect(forecast.lastDose == moment(10, 9))
        #expect(forecast.days == 2)
    }

    @Test func emptyBoxOnTheDayIsLow() {
        let evening = daily(hour: 21)
        let forecast = PillCount.forecast(course([evening], left: 0), reminders: [evening], now: now, calendar: calendar)
        #expect(forecast.pills == 0)
        #expect(forecast.days == 0)
        #expect(forecast.low)
    }

    @Test func brokenDoseFromSyncDoesNotCrash() {
        let evening = daily(hour: 21)
        var box = course([evening], left: 4)
        box.perDose = 0
        #expect(PillCount.left(box, reminders: [evening]) == 4)
        #expect(PillCount.forecast(box, reminders: [evening], now: now, calendar: calendar).pills == 4)
    }

    @Test func remindersOfOnePhraseShareTheBox() {
        let morning = daily(hour: 9)
        let evening = daily(" пить ТАБЛЕТКИ ", hour: 21)
        let water = daily("Пить воду", hour: 12)
        let once = Reminder(title: "Пить таблетки", schedule: Schedule(start: LocalDate(year: 2026, month: 11, day: 12), time: LocalTime(hour: 8, minute: 0)), createdAt: moment(1, 8))
        let ids = PillCount.siblings(of: evening, in: [morning, evening, water, once], courses: [])
        #expect(ids == [evening.id, morning.id])
        let other = PillCourse(reminderIDs: [morning.id], left: 10, counted: now)
        #expect(PillCount.siblings(of: evening, in: [morning, evening], courses: [other]) == [evening.id])
    }

    @Test func settingACourseReplacesAndRemoves() {
        var settings = Settings.standard(at: now)
        let first = PillCourse(reminderIDs: [UUID()], left: 10, counted: now)
        settings.setCourse(first, id: first.id)
        var changed = first
        changed.left = 30
        settings.setCourse(changed, id: first.id)
        #expect(settings.courses == [changed])
        #expect(settings.course(for: first.reminderIDs[0]) == changed)
        settings.setCourse(nil, id: first.id)
        #expect(settings.courses == [])
    }

    func merged(local: Settings, incoming: Settings) throws -> Settings {
        let snapshot = StoreSnapshot(reminders: [], places: [], settings: local, sounds: [])
        let record = SyncRecord(kind: SyncKind.prefs.rawValue, clientId: SyncState.settingsID, data: try JSONValue(encoding: incoming), clientUpdatedAt: SyncStamp.of(incoming.updatedAt), deleted: false, seq: 1)
        let response = SyncResponse(records: [record], rejected: [], cursor: 1, more: false)
        return SyncMerge.apply(response, sent: [], to: snapshot, state: SyncState(), now: now).snapshot.settings
    }

    @Test func anOlderBuildKeepsTheCourses() throws {
        var local = Settings.standard(at: now)
        local.touched = true
        local.courses = [PillCourse(reminderIDs: [UUID()], left: 12, counted: now)]
        var incoming = Settings.standard(at: now.addingTimeInterval(60))
        incoming.touched = true
        incoming.nagInterval = 10
        let result = try merged(local: local, incoming: incoming)
        #expect(result.nagInterval == 10)
        #expect(result.courses == local.courses)
    }

    @Test func aNewerBuildCanRemoveTheLastCourse() throws {
        var local = Settings.standard(at: now)
        local.touched = true
        local.courses = [PillCourse(reminderIDs: [UUID()], left: 12, counted: now)]
        var incoming = Settings.standard(at: now.addingTimeInterval(60))
        incoming.touched = true
        incoming.courses = []
        let result = try merged(local: local, incoming: incoming)
        #expect(result.courses == [])
    }
}
