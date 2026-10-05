import Foundation
import Testing
@testable import RemaCore

struct PhraseParserArabicTests {
    let parser = PhraseParser(
        now: PhraseParserTests.now,
        calendar: PhraseParserTests.calendar,
        morning: LocalTime(hour: 9, minute: 0),
        evening: LocalTime(hour: 19, minute: 0),
        places: ["المنزل", "العمل", "النادي"],
        preferred: "ar"
    )

    func when(_ phrase: ParsedPhrase) -> String? {
        guard let schedule = phrase.schedule else { return nil }
        return String(format: "%04d-%02d-%02d %02d:%02d", schedule.start.year, schedule.start.month, schedule.start.day, schedule.time.hour, schedule.time.minute)
    }

    @Test func tomorrowAtNine() {
        let result = parser.parse("غدا الساعة 9 اتصل بأمي")
        #expect(result.title == "اتصل بأمي")
        #expect(when(result) == "2026-10-06 09:00")
        #expect(result.highlights == [0..<3, 4..<12])
    }

    @Test func arabicDigitsAndDiacritics() {
        let result = parser.parse("غداً الساعة ٩ اتصل بأمي")
        #expect(result.title == "اتصل بأمي")
        #expect(when(result) == "2026-10-06 09:00")
    }

    @Test func offsets() {
        #expect(when(parser.parse("بعد ساعتين")) == "2026-10-05 15:50")
        let oven = parser.parse("بعد 20 دقيقة اطفئ الفرن")
        #expect(when(oven) == "2026-10-05 14:10")
        #expect(oven.title == "اطفئ الفرن")
        #expect(when(parser.parse("بعد نصف ساعة")) == "2026-10-05 14:20")
    }

    @Test func eveningAndWeekday() {
        let suit = parser.parse("الجمعة مساء استلام البدلة")
        #expect(suit.title == "استلام البدلة")
        #expect(when(suit) == "2026-10-09 19:00")
        #expect(when(parser.parse("اليوم الساعة 9 مساء اتصل بأبي")) == "2026-10-05 21:00")
    }

    @Test func repeats() {
        #expect(parser.parse("كل يوم الساعة 9 فيتامينات").schedule?.rule == .daily)
        let running = parser.parse("كل ثلاثاء وخميس الساعة 8 الجري")
        #expect(running.schedule?.rule == .weekly([.tuesday, .thursday]))
        #expect(when(running) == "2026-10-06 08:00")
        let birthday = parser.parse("كل سنة في 12 اكتوبر عيد ميلاد ساشا")
        #expect(birthday.schedule?.rule == .yearly(month: 10, day: 12))
        #expect(birthday.title == "عيد ميلاد ساشا")
    }

    @Test func alertsFlagsAndPlaces() {
        let dentist = parser.parse("غدا الساعة 15:00 طبيب الاسنان عاجل قبل ساعة")
        #expect(dentist.urgent)
        #expect(dentist.preAlerts == [60])
        #expect(when(dentist) == "2026-10-06 15:00")
        let parcel = parser.parse("عندما اغادر العمل استلام الطرد")
        #expect(parcel.placeTrigger == .leave)
        #expect(parcel.placeNames == ["العمل"])
        #expect(parcel.title == "استلام الطرد")
    }
}
