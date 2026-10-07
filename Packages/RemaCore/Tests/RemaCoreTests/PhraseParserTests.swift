import Foundation
import Testing
@testable import RemaCore

struct PhraseParserTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        return calendar
    }()

    static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 13, minute: 50))!

    let parser = PhraseParser(
        now: PhraseParserTests.now,
        calendar: PhraseParserTests.calendar,
        morning: LocalTime(hour: 9, minute: 0),
        evening: LocalTime(hour: 19, minute: 0),
        places: ["Дом", "Работа", "Спортзал"]
    )

    func when(_ phrase: ParsedPhrase) -> String? {
        guard let schedule = phrase.schedule else { return nil }
        return String(format: "%04d-%02d-%02d %02d:%02d", schedule.start.year, schedule.start.month, schedule.start.day, schedule.time.hour, schedule.time.minute)
    }

    @Test func tomorrowAtNine() {
        let result = parser.parse("завтра в 9 позвонить маме")
        #expect(result.title == "Позвонить маме")
        #expect(when(result) == "2026-10-06 09:00")
        #expect(result.schedule?.rule == nil)
        #expect(result.highlights == [0..<6, 7..<10])
    }

    @Test func inTwoHours() {
        #expect(when(parser.parse("через 2 часа")) == "2026-10-05 15:50")
        #expect(when(parser.parse("через 20 минут выключить духовку")) == "2026-10-05 14:10")
        #expect(parser.parse("через 20 минут выключить духовку").title == "Выключить духовку")
        #expect(when(parser.parse("через час")) == "2026-10-05 14:50")
        #expect(when(parser.parse("через полчаса")) == "2026-10-05 14:20")
    }

    @Test func fridayEvening() {
        let result = parser.parse("в пятницу вечером забрать костюм")
        #expect(result.title == "Забрать костюм")
        #expect(when(result) == "2026-10-09 19:00")
    }

    @Test func tuesdaysAndThursdays() {
        let result = parser.parse("каждый вт и чт в 8 бегать")
        #expect(result.title == "Бегать")
        #expect(result.schedule?.rule == .weekly([.tuesday, .thursday]))
        #expect(when(result) == "2026-10-06 08:00")
    }

    @Test func yearlyBirthday() {
        let result = parser.parse("каждый год 12 октября день рождения Саши")
        #expect(result.title == "День рождения Саши")
        #expect(result.schedule?.rule == .yearly(month: 10, day: 12))
        #expect(when(result) == "2026-10-12 09:00")
    }

    @Test func dateAndTime() {
        let result = parser.parse("15 октября в 18:30 стоматолог")
        #expect(result.title == "Стоматолог")
        #expect(when(result) == "2026-10-15 18:30")
    }

    @Test func urgentWithEarlyAlert() {
        let result = parser.parse("срочно в 14:30 позвонить поставщику за 15 минут")
        #expect(result.title == "Позвонить поставщику")
        #expect(result.urgent)
        #expect(result.preAlerts == [15])
        #expect(when(result) == "2026-10-05 14:30")
    }

    @Test func dailyPersistent() {
        let result = parser.parse("каждый день в 9 пить витамины настойчиво")
        #expect(result.title == "Пить витамины")
        #expect(result.nag)
        #expect(result.schedule?.rule == .daily)
        #expect(when(result) == "2026-10-06 09:00")
    }

    @Test func leavingWork() {
        let result = parser.parse("когда уйду с работы купить хлеб")
        #expect(result.title == "Купить хлеб")
        #expect(result.placeTrigger == .leave)
        #expect(result.placeNames == ["Работа"])
        #expect(result.schedule == nil)
    }

    @Test func arrivingHome() {
        let result = parser.parse("когда приду домой включить стирку")
        #expect(result.placeTrigger == .arrive)
        #expect(result.placeNames == ["Дом"])
        #expect(result.title == "Включить стирку")
    }

    @Test func fillerWordsAreDropped() {
        let result = parser.parse("напомни завтра купить молоко")
        #expect(result.title == "Купить молоко")
        #expect(when(result) == "2026-10-06 09:00")
    }

    @Test func timeOfDayWords() {
        #expect(when(parser.parse("в 7 вечера")) == "2026-10-05 19:00")
        #expect(when(parser.parse("в 3 дня")) == "2026-10-05 15:00")
        #expect(when(parser.parse("сегодня вечером")) == "2026-10-05 19:00")
        #expect(when(parser.parse("в 9 полить цветы")) == "2026-10-05 21:00")
        #expect(parser.parse("в 9 полить цветы").alternative == Schedule(start: LocalDate(year: 2026, month: 10, day: 6), time: LocalTime(hour: 9, minute: 0)))
        #expect(parser.parse("в 9 утра полить цветы").alternative == nil)
        #expect(when(parser.parse("в полдень обед")) == "2026-10-06 12:00")
        #expect(when(parser.parse("послезавтра в 10 встреча")) == "2026-10-07 10:00")
    }

    @Test func everyFewDays() {
        let result = parser.parse("каждые 3 дня полить кактус")
        #expect(result.schedule?.rule == .everyDays(3))
        #expect(result.title == "Полить кактус")
        #expect(when(result) == "2026-10-06 09:00")
    }

    @Test func monthlyOnTheSixth() {
        let result = parser.parse("каждый месяц 6-го оплатить интернет")
        #expect(result.schedule?.rule == .monthlyOnDay(6))
        #expect(result.title == "Оплатить интернет")
        #expect(when(result) == "2026-10-06 09:00")
    }

    @Test func inAWeek() {
        let result = parser.parse("через неделю позвонить в банк")
        #expect(result.title == "Позвонить в банк")
        #expect(when(result) == "2026-10-12 09:00")
    }

    @Test func severalEarlyAlerts() {
        let result = parser.parse("за неделю и за день оплатить сервер 6 октября в 10")
        #expect(result.preAlerts == [10_080, 1_440])
        #expect(result.title == "Оплатить сервер")
        #expect(when(result) == "2026-10-06 10:00")
    }

    @Test func plainTextHasNoSchedule() {
        let result = parser.parse("купить подарок")
        #expect(result.title == "Купить подарок")
        #expect(result.schedule == nil)
        #expect(result.highlights.isEmpty)
    }
}
