import Foundation
import Testing
@testable import RemaCore

struct PhraseMultiTests {
    let parser = PhraseParser(
        now: PhraseParserTests.now,
        calendar: PhraseParserTests.calendar,
        morning: LocalTime(hour: 9, minute: 0),
        evening: LocalTime(hour: 19, minute: 0),
        places: ["Дом", "Работа"]
    )

    func when(_ piece: PhrasePiece) -> String? {
        guard let schedule = piece.parsed.schedule else { return nil }
        return String(format: "%02d.%02d %02d:%02d", schedule.start.day, schedule.start.month, schedule.time.hour, schedule.time.minute)
    }

    @Test func threeRemindersShareTheDay() throws {
        let text = "завтра в 9 позвонить маме, в 12 обед с Ильёй, вечером купить хлеб"
        let pieces = try #require(parser.pieces(text))
        #expect(pieces.map(\.parsed.title) == ["Позвонить маме", "Обед с Ильёй", "Купить хлеб"])
        #expect(pieces.map(when) == ["06.10 09:00", "06.10 12:00", "06.10 19:00"])
        let words = pieces.flatMap(\.parsed.highlights).map { String(Array(text)[$0]) }
        #expect(words.contains("в 12"))
    }

    @Test func partWithoutTimeStaysWithThePreviousOne() throws {
        let pieces = try #require(parser.pieces("завтра в 9 позвонить маме, вечером купить хлеб и молоко"))
        #expect(pieces.map(\.parsed.title) == ["Позвонить маме", "Купить хлеб и молоко"])
    }

    @Test func oneThingIsNotSplit() {
        #expect(parser.pieces("купить хлеб, молоко и яйца завтра в 9") == nil)
        #expect(parser.pieces("в 9 позвонить маме и папе") == nil)
        #expect(parser.pieces("завтра в 17, нет, в 18 позвонить маме") == nil)
        #expect(parser.pieces("не в пятницу, а в субботу встреча") == nil)
        #expect(parser.pieces("через 1,5 часа забрать заказ") == nil)
        #expect(parser.pieces("завтра в 9 позвонить маме") == nil)
    }

    @Test func repeatCarriesOver() throws {
        let pieces = try #require(parser.pieces("every day at 9 take pills and at 21 vitamins"))
        #expect(pieces.map(\.parsed.title) == ["Take pills", "Vitamins"])
        #expect(pieces.map { $0.parsed.schedule?.rule } == [.daily, .daily])
        #expect(pieces.map(when) == ["06.10 09:00", "05.10 21:00"])
    }

    @Test func severalTimesADay() throws {
        let list = try #require(parser.pieces("каждый день в 9 и 21 пить таблетки"))
        #expect(list.map(\.parsed.title) == ["Пить таблетки", "Пить таблетки"])
        #expect(list.map(when) == ["06.10 09:00", "05.10 21:00"])
        #expect(list.allSatisfy { $0.parsed.schedule?.rule == .daily })
        let twice = try #require(parser.pieces("два раза в день пить воду"))
        #expect(twice.map(when) == ["06.10 09:00", "05.10 19:00"])
        #expect(try #require(parser.pieces("каждые 3 часа с 9 до 21 пить воду")).count == 5)
        #expect(try #require(parser.pieces("twice a day take vitamins")).map(\.parsed.title) == ["Take vitamins", "Take vitamins"])
        let titled = try #require(parser.pieces("в 9 и в 21 позвонить маме"))
        #expect(titled.map(when) == ["06.10 09:00", "05.10 21:00"])
        #expect(titled.allSatisfy { $0.parsed.schedule?.rule == nil })
    }

    @Test func serverWordsReadAsTheirMeaning() {
        var local = parser
        local.synonyms = ["завтрева": "завтра"]
        let result = local.parse("завтрева в 9 позвонить маме")
        #expect(result.title == "Позвонить маме")
        #expect(result.schedule?.start == LocalDate(year: 2026, month: 10, day: 6))
        #expect(result.highlights.first == 0..<8)
    }

    @Test func rangesPointIntoTheWholePhrase() throws {
        let text = "в 10 планёрка; в 15 звонок клиенту"
        let pieces = try #require(parser.pieces(text))
        #expect(pieces.map { String(Array(text)[$0.range]) } == ["в 10 планёрка", "в 15 звонок клиенту"])
    }
}
