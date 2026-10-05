import Foundation
import Testing
@testable import RemaCore

struct PhraseParserUzbekTests {
    let latin = PhraseParser(
        now: PhraseParserTests.now,
        calendar: PhraseParserTests.calendar,
        morning: LocalTime(hour: 9, minute: 0),
        evening: LocalTime(hour: 19, minute: 0),
        places: ["Uy", "Ish", "Sportzal"],
        preferred: "uz-Latn"
    )

    let cyrillic = PhraseParser(
        now: PhraseParserTests.now,
        calendar: PhraseParserTests.calendar,
        morning: LocalTime(hour: 9, minute: 0),
        evening: LocalTime(hour: 19, minute: 0),
        places: ["Уй", "Иш"],
        preferred: "uz-Cyrl"
    )

    func when(_ phrase: ParsedPhrase) -> String? {
        guard let schedule = phrase.schedule else { return nil }
        return String(format: "%04d-%02d-%02d %02d:%02d", schedule.start.year, schedule.start.month, schedule.start.day, schedule.time.hour, schedule.time.minute)
    }

    @Test func tomorrowAtNine() {
        let result = latin.parse("ertaga soat 9 da onamga qo‘ng‘iroq qilish")
        #expect(result.title == "Onamga qo‘ng‘iroq qilish")
        #expect(when(result) == "2026-10-06 09:00")
        #expect(result.highlights == [0..<6, 7..<16])
    }

    @Test func trailingRemindIsDropped() {
        #expect(latin.parse("ertaga soat 9:30 da non olishni eslat").title == "Non olishni")
    }

    @Test func offsets() {
        #expect(when(latin.parse("2 soatdan keyin")) == "2026-10-05 15:50")
        #expect(when(latin.parse("20 daqiqadan keyin pechni o‘chirish")) == "2026-10-05 14:10")
        #expect(when(latin.parse("yarim soatdan keyin")) == "2026-10-05 14:20")
    }

    @Test func eveningAndWeekday() {
        let suit = latin.parse("juma kuni kechqurun kostyumni olib kelish")
        #expect(suit.title == "Kostyumni olib kelish")
        #expect(when(suit) == "2026-10-09 19:00")
    }

    @Test func repeats() {
        #expect(latin.parse("har kuni soat 9 da vitaminlar").schedule?.rule == .daily)
        let running = latin.parse("har seshanba va payshanba soat 8 da yugurish")
        #expect(running.schedule?.rule == .weekly([.tuesday, .thursday]))
        #expect(when(running) == "2026-10-06 08:00")
        let birthday = latin.parse("har yili 12-oktyabr Sashaning tug‘ilgan kuni")
        #expect(birthday.schedule?.rule == .yearly(month: 10, day: 12))
    }

    @Test func alertsFlagsAndPlaces() {
        let dentist = latin.parse("ertaga soat 15:00 da tish shifokori shoshilinch bir soat oldin")
        #expect(dentist.urgent)
        #expect(dentist.preAlerts == [60])
        let parcel = latin.parse("ishdan ketganimda posilkani olish")
        #expect(parcel.placeTrigger == .leave)
        #expect(parcel.placeNames == ["Ish"])
        #expect(parcel.title == "Posilkani olish")
    }

    @Test func cyrillicMapsBackToTheOriginalText() {
        let result = cyrillic.parse("эртага соат 9 да онамга қўнғироқ қилиш")
        #expect(result.title == "Онамга қўнғироқ қилиш")
        #expect(when(result) == "2026-10-06 09:00")
        #expect(result.highlights == [0..<6, 7..<16])
        let parcel = cyrillic.parse("ишдан кетганимда посилкани олиш")
        #expect(parcel.placeNames == ["Иш"])
        #expect(parcel.placeTrigger == .leave)
    }

    @Test func russianUnderUzbekInterfaceStaysRussian() {
        #expect(cyrillic.parse("завтра в 9 позвонить маме").title == "Позвонить маме")
    }
}
