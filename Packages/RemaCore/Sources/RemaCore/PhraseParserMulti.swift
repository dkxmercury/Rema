import Foundation

public struct PhrasePiece: Equatable, Sendable {
    public var range: Range<Int>
    public var parsed: ParsedPhrase
}

extension PhraseParser {
    private static let joints = "\\s*(?:(?<!\\d),|,(?!\\d)|;|\\n)\\s*|\\s+(?:и|а потом|потом|затем|і|та|а потім|потім|and then|and|then|und dann|und|dann|et puis|puis|et|va keyin|keyin|va|ва кейин|кейин|ва|ثم|و)\\s+"

    // «Завтра в 9 позвонить маме, в 12 обед с Ильёй, вечером купить хлеб» is three reminders.
    // A part without its own time belongs to the one before it, «вечером купить хлеб и молоко» stays whole.
    public func pieces(_ input: String) -> [PhrasePiece]? {
        if let spread = spread(input) {
            return spread
        }
        guard !parse(input).corrected, let regex = try? NSRegularExpression(pattern: Self.joints, options: [.caseInsensitive]) else { return nil }
        var segments: [Range<String.Index>] = []
        var start = input.startIndex
        for match in regex.matches(in: input, range: NSRange(input.startIndex..., in: input)) {
            guard let range = Range(match.range, in: input) else { continue }
            segments.append(start..<range.lowerBound)
            start = range.upperBound
        }
        segments.append(start..<input.endIndex)
        segments = segments.filter { !input[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard segments.count >= 2, segments.count <= 20 else { return nil }

        var groups: [Range<String.Index>] = []
        var timed = false
        for segment in segments {
            let hasTime = parse(String(input[segment])).hasExplicitTime
            if let last = groups.last, !(hasTime && timed) {
                groups[groups.count - 1] = last.lowerBound..<segment.upperBound
                timed = timed || hasTime
            } else {
                groups.append(segment)
                timed = hasTime
            }
        }
        guard groups.count >= 2 else { return nil }

        var result: [PhrasePiece] = []
        var day: Schedule?
        for group in groups {
            let text = String(input[group])
            var parsed = parse(text)
            if parsed.hasExplicitDay {
                day = parsed.schedule
            } else if let day {
                parsed = carried(text, from: day)
            }
            guard parsed.hasExplicitTime, parsed.schedule != nil else { return nil }
            let offset = input.distance(from: input.startIndex, to: group.lowerBound)
            parsed.highlights = parsed.highlights.map { ($0.lowerBound + offset)..<($0.upperBound + offset) }
            result.append(PhrasePiece(range: offset..<(offset + text.count), parsed: parsed))
        }
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

    private static let spreads: [Spread] = [
        Spread(kind: .list, pattern: "(?:((?:\\d|два|две|три|четыре|пять) раза? в день) )?(в \\d{1,2}(?::\\d{2})?(?:(?:,| и) (?:в )?\\d{1,2}(?::\\d{2})?)+)", daily: "каждый день в %@", single: "в %@"),
        Spread(kind: .list, pattern: "(?:((?:\\d|два|дві|три|чотири) рази? на день) )?(о \\d{1,2}(?::\\d{2})?(?:(?:,| і| та) (?:о )?\\d{1,2}(?::\\d{2})?)+)", daily: "щодня о %@", single: "о %@"),
        Spread(kind: .list, pattern: "(?:((?:\\d|twice|two times|three times|four times) a day) )?(at \\d{1,2}(?::\\d{2})?(?: ?(?:am|pm))?(?:(?:,| and) (?:at )?\\d{1,2}(?::\\d{2})?(?: ?(?:am|pm))?)+)", daily: "every day at %@", single: "at %@"),
        Spread(kind: .list, pattern: "(?:((?:\\d|zwei|drei|vier) ?mal (?:am|pro) tag) )?(um \\d{1,2}(?::\\d{2})?(?:(?:,| und) (?:um )?\\d{1,2}(?::\\d{2})?)+)", daily: "jeden Tag um %@", single: "um %@"),
        Spread(kind: .list, pattern: "(?:((?:\\d|deux|trois|quatre) fois par jour) )?(à \\d{1,2}(?:[h:]\\d{0,2})?(?:(?:,| et) (?:à )?\\d{1,2}(?:[h:]\\d{0,2})?)+)", daily: "tous les jours à %@", single: "à %@"),
        Spread(kind: .perDay, pattern: "(\\d|два|две|три|четыре|пять) раза? в день", daily: "каждый день в %@", single: "в %@"),
        Spread(kind: .hours, pattern: "каждые (\\d) час\\w* с (\\d{1,2}) до (\\d{1,2})", daily: "каждый день в %@", single: "в %@"),
        Spread(kind: .perDay, pattern: "(\\d|два|дві|три|чотири|п'ять) рази? на день", daily: "щодня о %@", single: "о %@"),
        Spread(kind: .hours, pattern: "кожні (\\d) годин\\w* з (\\d{1,2}) до (\\d{1,2})", daily: "щодня о %@", single: "о %@"),
        Spread(kind: .perDay, pattern: "(\\d|twice|two times|three times|four times|five times) a day", daily: "every day at %@", single: "at %@"),
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

    // «В 9 и 21», «два раза в день» between the morning and the evening, «каждые 3 часа с 9 до 21»: every time becomes its own reminder.
    private func spread(_ input: String) -> [PhrasePiece]? {
        let lower = input.lowercased().replacingOccurrences(of: "’", with: "'")
        for spread in Self.spreads {
            guard let match = matches(spread.pattern, in: lower).first, let range = Range(match.range, in: lower) else { continue }
            var tokens: [String] = []
            var daily = true
            switch spread.kind {
            case .list:
                daily = group(match, 1, lower) != nil
                let region = group(match, 2, lower) ?? ""
                tokens = matches("\\d{1,2}(?:[:h]\\d{2})?(?: ?(?:am|pm))?", in: region).compactMap { found in
                    guard let place = Range(found.range, in: region) else { return nil }
                    let token = String(region[place])
                    if token.hasSuffix("m") {
                        return token
                    }
                    let parts = token.split(whereSeparator: { $0 == ":" || $0 == "h" }).compactMap { Int($0) }
                    guard let hour = parts.first, hour < 24, (parts.count < 2 || parts[1] < 60) else { return nil }
                    return String(format: "%02d:%02d", hour, parts.count > 1 ? parts[1] : 0)
                }
            case .perDay:
                let words = (1..<match.numberOfRanges).compactMap { group(match, $0, lower) }
                guard let word = words.first, let count = Int(word.filter(\.isNumber)) ?? Self.spreadCounts[word], (2...6).contains(count) else { continue }
                let first = morning.hour * 60 + morning.minute
                let last = max(evening.hour * 60 + evening.minute, first + 60)
                tokens = (0..<count).map { step in
                    let minutes = ((first + (last - first) * step / (count - 1)) + 2) / 5 * 5
                    return String(format: "%02d:%02d", minutes / 60, minutes % 60)
                }
            case .hours:
                let numbers = (1..<match.numberOfRanges).compactMap { group(match, $0, lower) }.compactMap { Int($0) }
                guard numbers.count == 3, numbers[0] >= 1, numbers[1] < numbers[2], numbers[2] <= 23 else { continue }
                tokens = stride(from: numbers[1], through: numbers[2], by: numbers[0]).prefix(12).map { String(format: "%02d:00", $0) }
            }
            guard tokens.count >= 2 else { continue }
            let characters = Array(input)
            let start = lower.distance(from: lower.startIndex, to: range.lowerBound)
            let length = lower.distance(from: range.lowerBound, to: range.upperBound)
            let before = String(characters[..<start])
            let after = String(characters[(start + length)...])
            var pieces: [PhrasePiece] = []
            for token in tokens {
                let time = (daily ? spread.daily : spread.single).replacingOccurrences(of: "%@", with: token)
                var parsed = parse((before + time + after).trimmingCharacters(in: .whitespaces))
                guard parsed.title.count >= 2, parsed.schedule != nil else { return nil }
                parsed.highlights = [start..<(start + length)]
                pieces.append(PhrasePiece(range: 0..<characters.count, parsed: parsed))
            }
            return pieces
        }
        return nil
    }

    // The day said in an earlier part holds for the next ones, «в 12» after «завтра в 9» is tomorrow at noon.
    // A repeat passes on as it is, «каждый день в 9 …, в 21 …» rings tonight already.
    private func carried(_ text: String, from schedule: Schedule) -> ParsedPhrase {
        if let rule = schedule.rule {
            var parsed = parse(text)
            if var own = parsed.schedule, own.rule == nil {
                own.rule = rule
                parsed.schedule = own
            }
            return parsed
        }
        let dayStart = calendar.date(from: DateComponents(year: schedule.start.year, month: schedule.start.month, day: schedule.start.day)) ?? now
        return PhraseParser(now: max(now, dayStart), calendar: calendar, morning: morning, evening: evening, places: places, preferred: preferred).parse(text)
    }
}
