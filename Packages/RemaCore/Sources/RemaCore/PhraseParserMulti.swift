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
            guard parsed.hasExplicitTime, parsed.schedule != nil, parsed.title.count >= 2 else { return nil }
            let offset = input.distance(from: input.startIndex, to: group.lowerBound)
            parsed.highlights = parsed.highlights.map { ($0.lowerBound + offset)..<($0.upperBound + offset) }
            result.append(PhrasePiece(range: offset..<(offset + text.count), parsed: parsed))
        }
        return result
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
