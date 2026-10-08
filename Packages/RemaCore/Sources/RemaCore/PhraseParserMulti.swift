import Foundation

public struct PhrasePiece: Equatable, Sendable {
    public var range: Range<Int>
    public var parsed: ParsedPhrase
}

extension PhraseParser {
    private static let joints = "\\s*(?:(?<!\\d),|,(?!\\d)|;|،|؛|\\n)\\s*|\\s+(?:и|а потом|потом|затем|і|та|а потім|потім|and then|and|then|und dann|und|dann|et puis|puis|et|va keyin|va|ва кейин|ва|ثم|و)\\s+|(?<!dan|дан)\\s+(?:keyin|кейин)\\s+"

    // «Завтра в 9 позвонить маме, в 12 обед с Ильёй, вечером купить хлеб» is three reminders.
    // A part without its own time or day belongs to the one before it, «вечером купить хлеб и молоко» stays whole.
    public func pieces(_ input: String) -> [PhrasePiece]? {
        let whole = parse(input)
        guard !whole.corrected, let regex = try? NSRegularExpression(pattern: Self.joints, options: [.caseInsensitive]) else { return nil }
        // A joint inside one time, «между 14 и 15» or «à huit heures et demie», or inside a list of times does not split.
        let kept = whole.highlights + [spreadRange(input)].compactMap { $0 }
        var segments: [Range<String.Index>] = []
        var start = input.startIndex
        for match in regex.matches(in: input, range: NSRange(input.startIndex..., in: input)) {
            guard let range = Range(match.range, in: input) else { continue }
            let lower = input.distance(from: input.startIndex, to: range.lowerBound)
            let upper = input.distance(from: input.startIndex, to: range.upperBound)
            guard !kept.contains(where: { $0.lowerBound <= lower && upper <= $0.upperBound }) else { continue }
            segments.append(start..<range.lowerBound)
            start = range.upperBound
        }
        segments.append(start..<input.endIndex)
        segments = segments.filter { !input[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard segments.count <= 20 else { return nil }
        guard segments.count >= 2 else { return spreadPieces(input, offset: 0, day: nil) }

        var groups: [Range<String.Index>] = []
        var timed = false
        for segment in segments {
            let parsed = parse(String(input[segment]))
            let hasWhen = parsed.hasExplicitTime || parsed.hasExplicitDay
            if let last = groups.last, !(hasWhen && timed) {
                groups[groups.count - 1] = last.lowerBound..<segment.upperBound
                timed = timed || hasWhen
            } else {
                groups.append(segment)
                timed = hasWhen
            }
        }
        // «Завтра вечером, в 8, ужин»: a part of the day with nothing else is the same time as the hour after it.
        var index = 0
        while index + 1 < groups.count {
            let current = parse(String(input[groups[index]]))
            let next = parse(String(input[groups[index + 1]]))
            if current.title.count < 2, current.usedPart != nil, next.hasExplicitTime, next.usedPart == nil {
                groups[index] = groups[index].lowerBound..<groups[index + 1].upperBound
                groups.remove(at: index + 1)
            } else {
                index += 1
            }
        }

        var result: [PhrasePiece] = []
        var day: Schedule?
        for group in groups {
            let text = String(input[group])
            let offset = input.distance(from: input.startIndex, to: group.lowerBound)
            if let spread = spreadPieces(text, offset: offset, day: day) {
                if let first = spread.first, first.parsed.hasExplicitDay {
                    day = first.parsed.schedule
                }
                result += spread
                continue
            }
            var parsed = parse(text)
            if parsed.hasExplicitDay {
                day = parsed.schedule
            } else if let day {
                parsed = carried(text, from: day)
            }
            guard parsed.hasExplicitTime || parsed.hasExplicitDay, parsed.schedule != nil else { return nil }
            parsed.highlights = parsed.highlights.map { ($0.lowerBound + offset)..<($0.upperBound + offset) }
            result.append(PhrasePiece(range: offset..<(offset + text.count), parsed: parsed))
        }
        guard result.count >= 2 else { return nil }
        // «В 9 и в 21 пить таблетки»: a part with only a time takes the title of its neighbour.
        for index in result.indices where result[index].parsed.title.count < 2 {
            let after = result[index...].first { $0.parsed.title.count >= 2 }
            let before = result[..<index].last { $0.parsed.title.count >= 2 }
            guard let title = (after ?? before)?.parsed.title else { return nil }
            result[index].parsed.title = title
        }
        return result
    }

    private struct Spread {
        enum Kind {
            case list
            case perDay
            case hours
        }

        let kind: Kind
        let pattern: String
        let daily: String
        let single: String
    }

    private static let ruNotTimes = "(?! (?:\(monthPattern)|\(ruCountedNouns)))"
    private static let ukNotTimes = "(?! (?:\(ukMonths)|клас\\w*|відсот\\w*|раз\\w*|людей|хвилин\\w*|годин\\w*))"
    private static let enNotTimes = "(?! (?:\(englishMonths)|percent|%|dollars?|euros?|people|times|stores|kids)(?![\\p{L}]))"
    private static let deNotTimes = "(?! (?:\(deMonths)|prozent|%|euro|leute|mal)(?![\\p{L}]))"
    private static let frNotTimes = "(?! (?:\(frMonths)|pour cent|%|euros?|personnes|fois)(?![\\p{L}]))"

    private static let spreads: [Spread] = [
        Spread(kind: .list, pattern: "(?:((?:\\d|два|две|три|четыре|пять) раза? в день) )?(в \\d{1,2}(?::\\d{2})?(?:(?:,| и) (?:в )?\\d{1,2}(?::\\d{2})?)+)\(ruNotTimes)", daily: "каждый день в %@", single: "в %@"),
        Spread(kind: .list, pattern: "(?:((?:\\d|два|дві|три|чотири) (?:рази?|разів) на день) )?(о \\d{1,2}(?::\\d{2})?(?:(?:,| і| та) (?:о )?\\d{1,2}(?::\\d{2})?)+)\(ukNotTimes)", daily: "щодня о %@", single: "о %@"),
        Spread(kind: .list, pattern: "(?:((?:twice|(?:\\d|two|three|four) times) a day) )?(at \\d{1,2}(?::\\d{2})?(?: ?(?:am|pm))?(?:(?:,| and) (?:at )?\\d{1,2}(?::\\d{2})?(?: ?(?:am|pm))?)+)\(enNotTimes)", daily: "every day at %@", single: "at %@"),
        Spread(kind: .list, pattern: "(?:((?:\\d|zwei|drei|vier) ?mal (?:am|pro) tag) )?(um \\d{1,2}(?::\\d{2})?(?:(?:,| und) (?:um )?\\d{1,2}(?::\\d{2})?)+)\(deNotTimes)", daily: "jeden Tag um %@", single: "um %@"),
        Spread(kind: .list, pattern: "(?:((?:\\d|deux|trois|quatre) fois par jour) )?(à \\d{1,2}(?:[h:]\\d{0,2})?(?:(?:,| et) (?:à )?\\d{1,2}(?:[h:]\\d{0,2})?)+)\(frNotTimes)", daily: "tous les jours à %@", single: "à %@"),
        Spread(kind: .perDay, pattern: "(\\d|два|две|три|четыре|пять) раза? в день", daily: "каждый день в %@", single: "в %@"),
        Spread(kind: .hours, pattern: "каждые (\\d) час\\w* с (\\d{1,2}) до (\\d{1,2})", daily: "каждый день в %@", single: "в %@"),
        Spread(kind: .perDay, pattern: "(\\d|два|дві|три|чотири|п'ять) (?:рази?|разів) на день", daily: "щодня о %@", single: "о %@"),
        Spread(kind: .hours, pattern: "кожні (\\d) годин\\w* з (\\d{1,2}) до (\\d{1,2})", daily: "щодня о %@", single: "о %@"),
        Spread(kind: .perDay, pattern: "(twice|(?:\\d|two|three|four|five) times) a day", daily: "every day at %@", single: "at %@"),
        Spread(kind: .hours, pattern: "every (\\d) hours from (\\d{1,2}) (?:to|till|until) (\\d{1,2})", daily: "every day at %@", single: "at %@"),
        Spread(kind: .perDay, pattern: "(\\d|zwei|drei|vier|fünf) ?mal (?:am|pro) tag|(zwei|drei|vier)mal täglich", daily: "jeden Tag um %@", single: "um %@"),
        Spread(kind: .hours, pattern: "alle (\\d) stunden von (\\d{1,2}) bis (\\d{1,2})", daily: "jeden Tag um %@", single: "um %@"),
        Spread(kind: .perDay, pattern: "(\\d|deux|trois|quatre|cinq) fois par jour", daily: "tous les jours à %@", single: "à %@"),
        Spread(kind: .hours, pattern: "toutes les (\\d) heures de (\\d{1,2})h? à (\\d{1,2})h?", daily: "tous les jours à %@", single: "à %@"),
        Spread(kind: .perDay, pattern: "kuniga (\\d|ikki|uch|to'rt|besh) marta", daily: "har kuni soat %@ da", single: "soat %@ da"),
        Spread(kind: .perDay, pattern: "(مرتين|ثلاث مرات|اربع مرات|\\d مرات) (?:في|ب)ال?يوم", daily: "كل يوم الساعة %@", single: "الساعة %@"),
    ]

    private static let spreadCounts: [String: Int] = [
        "два": 2, "две": 2, "три": 3, "четыре": 4, "пять": 5, "дві": 2, "чотири": 4, "п'ять": 5, "twice": 2, "two times": 2, "three times": 3,
        "four times": 4, "five times": 5, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5,
        "ikki": 2, "uch": 3, "to'rt": 4, "besh": 5, "مرتين": 2, "ثلاث مرات": 3, "اربع مرات": 4,
    ]

    private func spreadMatch(_ lower: String) -> (spread: Spread, match: NSTextCheckingResult, range: Range<String.Index>)? {
        for spread in Self.spreads {
            if let match = matches(spread.pattern, in: lower).first, let range = Range(match.range, in: lower) {
                return (spread, match, range)
            }
        }
        return nil
    }

    private func spreadRange(_ input: String) -> Range<Int>? {
        let lower = input.lowercased().replacingOccurrences(of: "’", with: "'")
        guard let found = spreadMatch(lower) else { return nil }
        let start = lower.distance(from: lower.startIndex, to: found.range.lowerBound)
        return start..<(start + lower.distance(from: found.range.lowerBound, to: found.range.upperBound))
    }

    // «В 9 и 21», «два раза в день» between the morning and the evening, «каждые 3 часа с 9 до 21»: every time becomes its own reminder.
    private func spreadPieces(_ input: String, offset: Int, day: Schedule?) -> [PhrasePiece]? {
        let lower = input.lowercased().replacingOccurrences(of: "’", with: "'")
        guard let (spread, match, range) = spreadMatch(lower) else { return nil }
        var tokens: [String] = []
        var daily = true
        switch spread.kind {
        case .list:
            daily = group(match, 1, lower) != nil
            let region = group(match, 2, lower) ?? ""
            let typed = matches("\\d{1,2}(?:[:h]\\d{2})?(?: ?(?:am|pm))?", in: region).compactMap { found -> String? in
                guard let place = Range(found.range, in: region) else { return nil }
                return String(region[place])
            }
            let hours = typed.map { token in Int(token.prefix { $0.isNumber }) ?? 99 }
            guard !hours.contains(where: { $0 > 23 }) else { return nil }
            // «В 9 и 21» is a 24-hour list; «в 8 и 10 вечером» or «at 9 and 10 pm» leave the hours to the words around them.
            if hours.contains(where: { $0 > 12 }) {
                tokens = typed.map { token in
                    let parts = token.split(whereSeparator: { $0 == ":" || $0 == "h" }).compactMap { Int($0) }
                    return String(format: "%02d:%02d", parts.first ?? 0, parts.count > 1 ? parts[1] : 0)
                }
            } else {
                let suffix = typed.last.flatMap { last in ["am", "pm"].first { last.hasSuffix($0) } }
                tokens = typed.map { token in
                    guard let suffix, !token.hasSuffix("m") else { return token }
                    return token + " " + suffix
                }
            }
        case .perDay:
            let words = (1..<match.numberOfRanges).compactMap { group(match, $0, lower) }
            guard let word = words.first, let count = Int(word.filter(\.isNumber)) ?? Self.spreadCounts[word], (2...6).contains(count) else { return nil }
            let first = morning.hour * 60 + morning.minute
            let last = max(evening.hour * 60 + evening.minute, first + 60)
            tokens = (0..<count).map { step in
                let minutes = ((first + (last - first) * step / (count - 1)) + 2) / 5 * 5
                return String(format: "%02d:%02d", minutes / 60, minutes % 60)
            }
        case .hours:
            let numbers = (1..<match.numberOfRanges).compactMap { group(match, $0, lower) }.compactMap { Int($0) }
            guard numbers.count == 3, numbers[0] >= 1, numbers[1] < numbers[2], numbers[2] <= 23 else { return nil }
            tokens = stride(from: numbers[1], through: numbers[2], by: numbers[0]).prefix(12).map { String(format: "%02d:00", $0) }
        }
        guard tokens.count >= 2 else { return nil }
        let characters = Array(input)
        let start = lower.distance(from: lower.startIndex, to: range.lowerBound)
        let length = lower.distance(from: range.lowerBound, to: range.upperBound)
        let before = String(characters[..<start])
        let after = String(characters[(start + length)...])
        // «По выходным 2 раза в день» keeps the weekends, «every day» is added only when nothing else repeats.
        if daily, parse((before + " " + after).trimmingCharacters(in: .whitespaces)).schedule?.rule != nil {
            daily = false
        }
        var pieces: [PhrasePiece] = []
        for token in tokens {
            let text = (before + (daily ? spread.daily : spread.single).replacingOccurrences(of: "%@", with: token) + after).trimmingCharacters(in: .whitespaces)
            var parsed = parse(text)
            if !parsed.hasExplicitDay, let day {
                parsed = carried(text, from: day)
            }
            guard parsed.title.count >= 2, parsed.schedule != nil else { return nil }
            parsed.highlights = [(offset + start)..<(offset + start + length)]
            pieces.append(PhrasePiece(range: offset..<(offset + characters.count), parsed: parsed))
        }
        return pieces
    }

    // The day said in an earlier part holds for the next ones, «в 12» after «завтра в 9» is tomorrow at noon.
    // A repeat passes on with its end, and a repeat counted from its first day keeps that day, «через день в 9 …, в 21 …».
    private func carried(_ text: String, from schedule: Schedule) -> ParsedPhrase {
        if let rule = schedule.rule {
            var parsed = parse(text)
            if var own = parsed.schedule, own.rule == nil {
                own.rule = rule
                own.end = schedule.end
                switch rule {
                case .everyDays, .everyMonths:
                    own.start = schedule.start
                default:
                    break
                }
                parsed.schedule = own
            }
            return parsed
        }
        let dayStart = calendar.date(from: DateComponents(year: schedule.start.year, month: schedule.start.month, day: schedule.start.day)) ?? now
        var inner = PhraseParser(now: max(now, dayStart), calendar: calendar, morning: morning, evening: evening, places: places, preferred: preferred)
        inner.coordinate = coordinate
        inner.synonyms = synonyms
        return inner.parse(text)
    }
}
