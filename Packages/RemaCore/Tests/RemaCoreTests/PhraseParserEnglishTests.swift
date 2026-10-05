import Foundation
import Testing
@testable import RemaCore

struct PhraseParserEnglishTests {
    let parser = PhraseParser(
        now: PhraseParserTests.now,
        calendar: PhraseParserTests.calendar,
        morning: LocalTime(hour: 9, minute: 0),
        evening: LocalTime(hour: 19, minute: 0),
        places: ["Home", "Work", "Gym"]
    )

    func when(_ phrase: ParsedPhrase) -> String? {
        guard let schedule = phrase.schedule else { return nil }
        return String(format: "%04d-%02d-%02d %02d:%02d", schedule.start.year, schedule.start.month, schedule.start.day, schedule.time.hour, schedule.time.minute)
    }

    @Test func tomorrowAtNine() {
        let result = parser.parse("tomorrow at 9 call mom")
        #expect(result.title == "Call mom")
        #expect(when(result) == "2026-10-06 09:00")
        #expect(result.highlights == [0..<8, 9..<13])
    }

    @Test func remindMePrefixIsDropped() {
        let result = parser.parse("Remind me to call mom tomorrow at 9am")
        #expect(result.title == "Call mom")
        #expect(when(result) == "2026-10-06 09:00")
    }

    @Test func meridiemAndMinutes() {
        #expect(when(parser.parse("pay rent at 7:30 pm")) == "2026-10-05 19:30")
        #expect(when(parser.parse("standup 10am")) == "2026-10-06 10:00")
        #expect(when(parser.parse("lunch at noon")) == "2026-10-06 12:00")
    }

    @Test func inTwoHours() {
        #expect(when(parser.parse("in 2 hours")) == "2026-10-05 15:50")
        #expect(when(parser.parse("in 20 minutes turn off the oven")) == "2026-10-05 14:10")
        #expect(parser.parse("in 20 minutes turn off the oven").title == "Turn off the oven")
        #expect(when(parser.parse("in an hour")) == "2026-10-05 14:50")
        #expect(when(parser.parse("in half an hour")) == "2026-10-05 14:20")
    }

    @Test func fridayEvening() {
        let result = parser.parse("pick up the suit on friday evening")
        #expect(result.title == "Pick up the suit")
        #expect(when(result) == "2026-10-09 19:00")
    }

    @Test func tonightMakesTheHourEvening() {
        #expect(when(parser.parse("call dad tonight at 9")) == "2026-10-05 21:00")
    }

    @Test func tuesdaysAndThursdays() {
        let result = parser.parse("every tue and thu at 8 go running")
        #expect(result.title == "Go running")
        #expect(result.schedule?.rule == .weekly([.tuesday, .thursday]))
        #expect(when(result) == "2026-10-06 08:00")
    }

    @Test func yearlyBirthday() {
        let result = parser.parse("every year on October 12 Sasha's birthday")
        #expect(result.title == "Sasha's birthday")
        #expect(result.schedule?.rule == .yearly(month: 10, day: 12))
        #expect(when(result) == "2026-10-12 09:00")
    }

    @Test func dailyAndWeekdays() {
        #expect(parser.parse("take vitamins every day at 9").schedule?.rule == .daily)
        #expect(parser.parse("check mail on weekdays at 10").schedule?.rule == .weekdays)
        #expect(parser.parse("water plants every 3 days").schedule?.rule == .everyDays(3))
    }

    @Test func monthly() {
        let result = parser.parse("pay internet on the 15th of every month")
        #expect(result.schedule?.rule == .monthlyOnDay(15))
        #expect(when(result) == "2026-10-15 09:00")
        #expect(result.title == "Pay internet")
    }

    @Test func alertsAndFlags() {
        let result = parser.parse("dentist tomorrow at 15:00 urgent, an hour before and a day before")
        #expect(result.urgent)
        #expect(result.preAlerts == [1_440, 60])
        #expect(when(result) == "2026-10-06 15:00")
        #expect(parser.parse("take pills at 21:00 until I mark it").nag)
    }

    @Test func places() {
        let leave = parser.parse("when I leave work pick up the parcel")
        #expect(leave.placeTrigger == .leave)
        #expect(leave.placeNames == ["Work"])
        #expect(leave.title == "Pick up the parcel")
        #expect(leave.schedule == nil)
        let home = parser.parse("when I get home feed the cat")
        #expect(home.placeTrigger == .arrive)
        #expect(home.placeNames == ["Home"])
    }

    @Test func dates() {
        #expect(when(parser.parse("passport office on October 20 at 11")) == "2026-10-20 11:00")
        #expect(when(parser.parse("concert 3rd of November at 19:00")) == "2026-11-03 19:00")
        #expect(when(parser.parse("the day after tomorrow")) == "2026-10-07 09:00")
    }

    @Test func russianStillGoesToRussianRules() {
        #expect(parser.parse("завтра в 9 позвонить маме").title == "Позвонить маме")
    }
}
