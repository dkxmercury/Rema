import Foundation
import Testing
@testable import RemaCore

struct PhraseParserUkrainianTests {
    let parser = PhraseParser(
        now: PhraseParserTests.now,
        calendar: PhraseParserTests.calendar,
        morning: LocalTime(hour: 9, minute: 0),
        evening: LocalTime(hour: 19, minute: 0),
        places: ["Дім", "Робота", "Спортзал"],
        preferred: "uk"
    )

    func when(_ phrase: ParsedPhrase) -> String? {
        guard let schedule = phrase.schedule else { return nil }
        return String(format: "%04d-%02d-%02d %02d:%02d", schedule.start.year, schedule.start.month, schedule.start.day, schedule.time.hour, schedule.time.minute)
    }

    @Test func tomorrowAtNine() {
        let result = parser.parse("завтра о 9 подзвонити мамі")
        #expect(result.title == "Подзвонити мамі")
        #expect(when(result) == "2026-10-06 09:00")
    }

    @Test func remindPrefixIsDropped() {
        #expect(parser.parse("нагадай мені завтра о 9:30 купити хліб").title == "Купити хліб")
    }

    @Test func inTwoHours() {
        #expect(when(parser.parse("через 2 години")) == "2026-10-05 15:50")
        #expect(when(parser.parse("через 20 хвилин вимкнути духовку")) == "2026-10-05 14:10")
        #expect(when(parser.parse("через півгодини")) == "2026-10-05 14:20")
    }

    @Test func fridayEvening() {
        let result = parser.parse("у п'ятницю ввечері забрати костюм")
        #expect(result.title == "Забрати костюм")
        #expect(when(result) == "2026-10-09 19:00")
    }

    @Test func repeats() {
        #expect(parser.parse("щодня о 9 вітаміни").schedule?.rule == .daily)
        #expect(parser.parse("кожен вт і чт о 8 бігати").schedule?.rule == .weekly([.tuesday, .thursday]))
        #expect(parser.parse("щопонеділка о 10 планування").schedule?.rule == .weekly([.monday]))
        let birthday = parser.parse("щороку 12 жовтня день народження Саші")
        #expect(birthday.schedule?.rule == .yearly(month: 10, day: 12))
        #expect(birthday.title == "День народження Саші")
    }

    @Test func alertsFlagsAndPlaces() {
        let result = parser.parse("завтра о 15:00 стоматолог терміново за годину")
        #expect(result.urgent)
        #expect(result.preAlerts == [60])
        let leave = parser.parse("коли піду з роботи забрати посилку")
        #expect(leave.placeTrigger == .leave)
        #expect(leave.placeNames == ["Робота"])
        #expect(leave.title == "Забрати посилку")
    }

    @Test func russianStaysRussianWithoutUkrainianLetters() {
        let russian = PhraseParser(now: PhraseParserTests.now, calendar: PhraseParserTests.calendar, morning: LocalTime(hour: 9, minute: 0), evening: LocalTime(hour: 19, minute: 0))
        #expect(russian.parse("завтра в 9 позвонить маме").title == "Позвонить маме")
    }
}
