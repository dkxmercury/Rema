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

    @Test func rangesPointIntoTheWholePhrase() throws {
        let text = "в 10 планёрка; в 15 звонок клиенту"
        let pieces = try #require(parser.pieces(text))
        #expect(pieces.map { String(Array(text)[$0.range]) } == ["в 10 планёрка", "в 15 звонок клиенту"])
    }
}
