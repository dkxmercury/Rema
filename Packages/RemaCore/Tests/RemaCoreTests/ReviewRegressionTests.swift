import Foundation
import Testing
@testable import RemaCore

// Phrases the check of 2026-10-08 found broken after «Обновление 82».
struct ReviewRegressionTests {
    let parser = PhraseParser(
        now: PhraseParserTests.now,
        calendar: PhraseParserTests.calendar,
        morning: LocalTime(hour: 9, minute: 0),
        evening: LocalTime(hour: 19, minute: 0),
        places: []
    )

    func clock(_ schedule: Schedule?) -> String? {
        schedule.map { String(format: "%02d:%02d", $0.time.hour, $0.time.minute) }
    }

    @Test func ukrainianHourAfterNa() {
        let doctor = parser.parse("завтра на 10 годину до лікаря")
        #expect(clock(doctor.schedule) == "10:00")
        #expect(!doctor.title.lowercased().contains("годину"))
        #expect(clock(parser.parse("у п'ятницю на 15 годину перукар").schedule) == "15:00")
        #expect(clock(parser.parse("у суботу на 21 годину кіно").schedule) == "21:00")
        let room = parser.parse("забронювати переговорку на 1 годину завтра")
        #expect(clock(room.schedule) == "09:00")
        #expect(room.title.contains("на 1 годину"))
    }

    @Test func ukrainianWeekdayRangeIsNotEveryFriday() {
        let rule = parser.parse("з понеділка по п'ятницю о 8 зарядка").schedule?.rule
        if case .weekly(let days) = rule {
            #expect(days.count == 5)
        } else {
            #expect(rule == .weekdays)
        }
    }

    @Test func weeklyBeforeANounWithADayRepeats() {
        for phrase in ["weekly meeting on Monday at 10", "haftalik yig‘ilish dushanba soat 10 da"] {
            guard case .weekly(let days) = parser.parse(phrase).schedule?.rule else {
                Issue.record("not weekly: \(phrase)")
                continue
            }
            #expect(days.count == 1)
        }
        #expect(parser.parse("prepare the weekly report tomorrow at 10").schedule?.rule == nil)
    }

    @Test func laterPartsOfAPhraseGetTheAfternoonToo() throws {
        let pieces = try #require(parser.pieces("завтра в 3 забрать детей, в 5 тренировка"))
        #expect(pieces.map { clock($0.parsed.schedule) } == ["15:00", "17:00"])
    }

    @Test func aWednesdayAfterAndIsAWeekday() {
        let parsed = parser.parse("во вторник и среду позвонить маме")
        #expect(parsed.title == "Позвонить маме")
    }

    @Test func aPrepositionLaterInTheItemDoesNotStopTheList() {
        #expect(Checklist.items(in: "купить молоко и хлеб с маслом") == ["Молоко", "Хлеб с маслом"])
        #expect(Checklist.items(in: "buy milk and bread for the party") == ["Milk", "Bread for the party"])
        #expect(Checklist.items(in: "купить корм для кошки и собаки").count < 2)
    }
}
