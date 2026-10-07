import Foundation
import Testing
@testable import RemaCore

// Living phrases with the answer they must give. A known gap is marked and does not fail the run, until it starts passing.
struct CorpusCase: Sendable, CustomTestStringConvertible {
    let phrase: String
    let expected: String
    let gap: Bool

    var testDescription: String { phrase }
}

func ok(_ phrase: String, _ expected: String) -> CorpusCase {
    CorpusCase(phrase: phrase, expected: expected, gap: false)
}

func gap(_ phrase: String, _ expected: String) -> CorpusCase {
    CorpusCase(phrase: phrase, expected: expected, gap: true)
}

enum Corpus {
    static let places: [String: [String]] = [
        "ru": ["Дом", "Работа", "Спортзал"],
        "uk": ["Дім", "Робота", "Спортзал"],
        "en": ["Home", "Work", "Gym"],
        "de": ["Zuhause", "Arbeit", "Fitnessstudio"],
        "fr": ["Maison", "Travail", "Salle de sport"],
        "uz-Latn": ["Uy", "Ish", "Sport zal"],
        "uz-Cyrl": ["Уй", "Иш", "Спорт зал"],
        "ar": ["البيت", "العمل", "النادي"],
    ]

    static func parser(_ language: String) -> PhraseParser {
        PhraseParser(
            now: PhraseParserTests.now,
            calendar: PhraseParserTests.calendar,
            morning: LocalTime(hour: 9, minute: 0),
            evening: LocalTime(hour: 19, minute: 0),
            places: places[language] ?? [],
            preferred: language
        )
    }

    static func summary(_ phrase: ParsedPhrase) -> String {
        var when = "-"
        var repeats = "-"
        if let schedule = phrase.schedule {
            when = String(format: "%02d.%02d %02d:%02d", schedule.start.day, schedule.start.month, schedule.time.hour, schedule.time.minute)
            // A repeat may be anchored before its first real occurrence, the person sees the occurrence.
            if schedule.rule != nil, let first = Recurrence.next(schedule, after: PhraseParserTests.now.addingTimeInterval(-1), limit: 1, calendar: PhraseParserTests.calendar).first {
                let parts = PhraseParserTests.calendar.dateComponents([.day, .month, .hour, .minute], from: first)
                when = String(format: "%02d.%02d %02d:%02d", parts.day ?? 0, parts.month ?? 0, parts.hour ?? 0, parts.minute ?? 0)
            }
            if let rule = schedule.rule {
                repeats = describe(rule)
            }
            switch schedule.end {
            case .never:
                break
            case .until(let last):
                repeats += String(format: " until %02d.%02d.%04d", last.day, last.month, last.year)
            case .count(let total):
                repeats += " x\(total)"
            }
        }
        var extras: [String] = []
        if phrase.urgent {
            extras.append("urgent")
        }
        if phrase.nag {
            extras.append("nag")
        }
        if !phrase.preAlerts.isEmpty {
            extras.append("early " + phrase.preAlerts.sorted().map(String.init).joined(separator: ","))
        }
        if let other = phrase.alternative {
            extras.append(String(format: "alt %02d.%02d %02d:%02d", other.start.day, other.start.month, other.time.hour, other.time.minute))
        }
        if let trigger = phrase.placeTrigger, !phrase.placeNames.isEmpty {
            extras.append("\(trigger.rawValue) " + phrase.placeNames.joined(separator: ","))
        }
        return [phrase.title, when, repeats, extras.isEmpty ? "-" : extras.joined(separator: "; ")].joined(separator: " | ")
    }

    static func describe(_ rule: RepeatRule) -> String {
        switch rule {
        case .daily: return "daily"
        case .weekdays: return "weekdays"
        case .weekly(let days): return "weekly " + days.sorted().map(code).joined(separator: ",")
        case .everyDays(let count): return "every \(count)d"
        case .monthlyOnDay(let day): return "monthly \(day)"
        case .monthlyOnWeekday(let ordinal, let weekday): return "monthly \(ordinal) \(code(weekday))"
        case .yearly(let month, let day): return String(format: "yearly %02d.%02d", day, month)
        }
    }

    static func code(_ day: Weekday) -> String {
        ["mon", "tue", "wed", "thu", "fri", "sat", "sun"][day.rawValue - 1]
    }

    static func check(_ item: CorpusCase, _ language: String) {
        let actual = summary(parser(language).parse(item.phrase))
        if item.gap {
            withKnownIssue("not understood yet") {
                #expect(actual == item.expected, "\(item.phrase)")
            }
        } else {
            #expect(actual == item.expected, "\(item.phrase)")
        }
    }
}

struct PhraseCorpusTests {
    @Test(arguments: CorpusData.russian) func russian(_ item: CorpusCase) { Corpus.check(item, "ru") }
    @Test(arguments: CorpusData.ukrainian) func ukrainian(_ item: CorpusCase) { Corpus.check(item, "uk") }
    @Test(arguments: CorpusData.english) func english(_ item: CorpusCase) { Corpus.check(item, "en") }
    @Test(arguments: CorpusData.german) func german(_ item: CorpusCase) { Corpus.check(item, "de") }
    @Test(arguments: CorpusData.french) func french(_ item: CorpusCase) { Corpus.check(item, "fr") }
    @Test(arguments: CorpusData.uzbekLatin) func uzbekLatin(_ item: CorpusCase) { Corpus.check(item, "uz-Latn") }
    @Test(arguments: CorpusData.uzbekCyrillic) func uzbekCyrillic(_ item: CorpusCase) { Corpus.check(item, "uz-Cyrl") }
    @Test(arguments: CorpusData.arabic) func arabic(_ item: CorpusCase) { Corpus.check(item, "ar") }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CORPUS_DUMP"] != nil)) func dump() {
        let all: [(String, [CorpusCase])] = [("ru", CorpusData.russian), ("uk", CorpusData.ukrainian), ("en", CorpusData.english), ("de", CorpusData.german), ("fr", CorpusData.french), ("uz-Latn", CorpusData.uzbekLatin), ("uz-Cyrl", CorpusData.uzbekCyrillic), ("ar", CorpusData.arabic)]
        for (language, cases) in all {
            for item in cases {
                print("CORPUS\t\(language)\t\(item.phrase)\t\(Corpus.summary(Corpus.parser(language).parse(item.phrase)))")
            }
        }
    }
}
