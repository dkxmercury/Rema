import Foundation
import Testing
@testable import RemaCore

struct OutsideTests {
    private let now = Date(timeIntervalSince1970: 1_791_500_000)

    private func item(_ data: String, doneThrough: Int64 = 0, id: String = "8A3C4F2E-1B2D-4C5E-9F60-123456789ABC") throws -> SharedItem {
        let json = """
        {"id":"\(id)","owner":{"id":"abcdefghijklmno","name":"Аня"},"data":\(data),"myStatus":"accepted","doneThrough":\(doneThrough),"myDone":0,"seq":5,"members":[]}
        """
        return try JSONDecoder().decode(SharedItem.self, from: Data(json.utf8))
    }

    @Test func aScheduleFarOutOfRangeIsDroppedBeforeAnyArithmetic() throws {
        let huge = try item(#"{"title":"Кино","schedule":{"start":{"year":1000000000000000,"month":1,"day":1},"time":{"hour":9,"minute":0},"rule":{"daily":{}},"end":{"never":{}}},"doneMode":"each"}"#)
        #expect(huge.data?.schedule == nil)
        let step = try item(#"{"title":"Кино","schedule":{"start":{"year":2026,"month":10,"day":9},"time":{"hour":9,"minute":0},"rule":{"everyDays":{"_0":9223372036854775807}},"end":{"never":{}}},"doneMode":"each"}"#)
        #expect(step.data?.schedule == nil)
        let fine = try item(#"{"title":"Кино","schedule":{"start":{"year":2026,"month":10,"day":9},"time":{"hour":21,"minute":30},"rule":{"everyDays":{"_0":3}},"end":{"count":{"_0":4}}},"doneMode":"each"}"#, id: "0E7D9F4A-5B6C-4D7E-8F90-ABCDEF123456")
        #expect(fine.data?.schedule?.rule == .everyDays(3))
        let merged = SharedMerge.apply([huge, fine], to: [], waiting: [], now: now)
        #expect(merged.count == 2)
        for reminder in merged {
            _ = Recurrence.next(reminder.schedule ?? Schedule(start: LocalDate(year: 2026, month: 1, day: 1), time: LocalTime(hour: 1, minute: 0)), after: now, limit: 3, calendar: .current)
        }
    }

    @Test func aTickFromTheFarFutureIsNotATick() throws {
        let item = try item(#"{"title":"Кино","schedule":null,"doneMode":"one"}"#, doneThrough: Int64.max)
        #expect(item.doneThrough == 0)
        let merged = SharedMerge.apply([item], to: [], waiting: [], now: now)
        #expect(merged.first?.completedThrough == nil)
        #expect(Date(timeIntervalSince1970: 1e300).milliseconds == 9_000_000_000_000_000_000)
        #expect(Int64(7_258_118_400_001).asMilliseconds == 0)
        #expect(Int64(-5).asMilliseconds == 0)
    }

    @Test func dateArithmeticNeverTraps() {
        let far = LocalDate(year: Int.max / 2, month: 3, day: 1)
        _ = far.adding(days: Int.max / 2)
        _ = LocalDate(dayNumber: Int.max).adding(days: 1)
    }

    @Test func namesLoseTheirTricks() {
        #expect("\u{202E}Rema\u{202C} Support\n\tTeam".cleanedName() == "Rema Support Team")
        #expect(String(repeating: "a", count: 90).cleanedName().count == 40)
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} Семья"
        #expect(family.cleanedName() == family)
        #expect("  Аня   Петрова  ".cleanedName() == "Аня Петрова")
    }

    @Test func aListOfTheSameHourIsOneReminder() {
        let parser = PhraseParser(now: now, calendar: .current, morning: LocalTime(hour: 9, minute: 0), evening: LocalTime(hour: 19, minute: 0))
        let phrase = "купить хлеб " + Array(repeating: "в 9", count: 40).joined(separator: ", ")
        let pieces = parser.pieces(phrase)
        #expect((pieces?.count ?? 1) <= 1)
    }

    @Test func aPlaceOffTheMapIsRefused() {
        let json = #"{"id":"8A3C4F2E-1B2D-4C5E-9F60-123456789ABC","name":"Дом","icon":"home","latitude":9999,"longitude":1,"radius":5e300,"createdAt":0,"updatedAt":0}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Place.self, from: Data(json.utf8))
        }
        let wide = #"{"id":"8A3C4F2E-1B2D-4C5E-9F60-123456789ABC","name":"Дом","icon":"home","latitude":41.3,"longitude":69.2,"radius":5e300,"createdAt":0,"updatedAt":0}"#
        let place = try? JSONDecoder().decode(Place.self, from: Data(wide.utf8))
        #expect(place?.radius == Place.radiusRange.upperBound)
    }
}
