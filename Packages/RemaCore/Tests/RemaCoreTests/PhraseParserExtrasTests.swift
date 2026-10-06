import Foundation
import Testing
@testable import RemaCore

struct PhraseParserExtrasTests {
    func parser(_ preferred: String) -> PhraseParser {
        PhraseParser(
            now: PhraseParserTests.now,
            calendar: PhraseParserTests.calendar,
            morning: LocalTime(hour: 9, minute: 0),
            evening: LocalTime(hour: 19, minute: 0),
            preferred: preferred
        )
    }

    func when(_ phrase: ParsedPhrase) -> String? {
        guard let schedule = phrase.schedule else { return nil }
        return String(format: "%04d-%02d-%02d %02d:%02d", schedule.start.year, schedule.start.month, schedule.start.day, schedule.time.hour, schedule.time.minute)
    }

    @Test func russian() {
        let ru = parser("ru")
        let lunch = ru.parse("в обед позвонить в банк")
        #expect(when(lunch) == "2026-10-06 13:00")
        #expect(lunch.title == "Позвонить в банк")
        #expect(when(ru.parse("после работы купить хлеб")) == "2026-10-05 18:30")
        #expect(when(ru.parse("на выходных помыть машину")) == "2026-10-10 09:00")
        let weekends = ru.parse("каждые выходные звонить родителям")
        #expect(weekends.schedule?.rule == .weekly([.saturday, .sunday]))
        #expect(when(ru.parse("в конце месяца оплатить квартиру")) == "2026-10-31 09:00")
        #expect(ru.parse("каждый последний день месяца сдать отчёт").schedule?.rule == .monthlyOnDay(31))
        let pills = ru.parse("через день пить таблетки")
        #expect(pills.schedule?.rule == .everyDays(2))
        #expect(pills.title == "Пить таблетки")
        let tuesday = ru.parse("каждый второй вторник полить цветы")
        #expect(tuesday.schedule?.rule == .everyDays(14))
        #expect(when(tuesday) == "2026-10-06 09:00")
        #expect(ru.parse("каждый второй вторник месяца собрание").schedule?.rule == .monthlyOnWeekday(ordinal: 2, weekday: .tuesday))
        #expect(ru.parse("в последнюю пятницу месяца").schedule?.rule == .monthlyOnWeekday(ordinal: -1, weekday: .friday))
    }

    @Test func english() {
        let en = parser("en")
        let lunch = en.parse("at lunch call the bank")
        #expect(when(lunch) == "2026-10-06 13:00")
        #expect(lunch.title == "Call the bank")
        #expect(when(en.parse("after work buy bread")) == "2026-10-05 18:30")
        #expect(when(en.parse("this weekend wash the car")) == "2026-10-10 09:00")
        #expect(en.parse("every other day take pills").schedule?.rule == .everyDays(2))
        #expect(en.parse("every other tuesday water the plants").schedule?.rule == .everyDays(14))
        #expect(en.parse("on the last friday of every month pay rent").schedule?.rule == .monthlyOnWeekday(ordinal: -1, weekday: .friday))
        #expect(when(en.parse("at the end of the month pay rent")) == "2026-10-31 09:00")
    }

    @Test func ukrainian() {
        let uk = parser("uk")
        #expect(when(uk.parse("на вихідних помити машину")) == "2026-10-10 09:00")
        #expect(uk.parse("через день пити ліки").schedule?.rule == .everyDays(2))
        #expect(when(uk.parse("після роботи купити хліб")) == "2026-10-05 18:30")
    }

    @Test func uzbek() {
        let uz = parser("uz-Latn")
        #expect(uz.parse("kunora dori ichish").schedule?.rule == .everyDays(2))
        #expect(when(uz.parse("tushlikda bankka qo'ng'iroq qilish")) == "2026-10-06 13:00")
        #expect(when(uz.parse("oy oxirida ijara to'lash")) == "2026-10-31 09:00")
    }

    @Test func arabic() {
        let ar = parser("ar")
        #expect(ar.parse("كل يومين شرب الدواء").schedule?.rule == .everyDays(2))
        #expect(when(ar.parse("في نهاية الشهر دفع الإيجار")) == "2026-10-31 09:00")
        #expect(when(ar.parse("بعد العمل شراء الخبز")) == "2026-10-05 18:30")
    }

    @Test func french() {
        let fr = parser("fr")
        #expect(fr.parse("un mardi sur deux arroser les plantes").schedule?.rule == .everyDays(14))
        #expect(fr.parse("tous les deux jours prendre les médicaments").schedule?.rule == .everyDays(2))
        #expect(when(fr.parse("à la fin du mois payer le loyer")) == "2026-10-31 09:00")
    }

    @Test func german() {
        let de = parser("de")
        #expect(de.parse("jeden zweiten Dienstag Pflanzen gießen").schedule?.rule == .everyDays(14))
        #expect(when(de.parse("am Wochenende Auto waschen")) == "2026-10-10 09:00")
        #expect(when(de.parse("nach der Arbeit einkaufen")) == "2026-10-05 18:30")
    }
}
