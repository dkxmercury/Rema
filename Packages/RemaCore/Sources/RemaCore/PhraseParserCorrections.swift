import Foundation

extension PhraseParser {
    struct Correction {
        var marker: String
        var contrast: String
        var negation: String?
    }

    // «Завтра в 17, нет, в 18» and «не в пятницу, а в субботу». The phrase is read again without the value that was taken back.
    func corrected(_ text: String, _ words: Correction, _ pass: (String, inout State) -> Void) -> State {
        var state = State()
        pass(text, &state)
        var removed: [Range<Int>] = []
        var gaps: [Range<Int>] = []
        var dropped: [Mark] = []
        var current = text
        var rounds = 0
        while rounds < 3, let next = takenBack(in: current, state, words) {
            rounds += 1
            removed.append(contentsOf: next.ranges)
            gaps.append(next.gap)
            dropped.append(contentsOf: next.marks)
            var characters = Array(text)
            for range in removed {
                for index in range where index < characters.count {
                    characters[index] = " "
                }
            }
            current = String(characters)
            state = State()
            pass(current, &state)
        }
        state.used.append(contentsOf: removed + gaps)
        // «В 7 вечера, нет, в 8»: the replacement keeps the half of the day of what it replaced.
        if let earlier = dropped.last(where: { $0.time && $0.clock != nil }), let clock = earlier.clock, earlier.meridiem || clock.hour >= 12,
           let time = state.time, (1...11).contains(time.hour), !state.meridiem, state.dayPart == nil {
            state.time = LocalTime(hour: clock.hour >= 12 ? time.hour + 12 : time.hour, minute: time.minute)
            state.meridiem = true
        }
        return state
    }

    // Values standing together form a group; a correction word between two groups takes back the values of the first one that the second one names again.
    private func takenBack(in text: String, _ state: State, _ words: Correction) -> (ranges: [Range<Int>], gap: Range<Int>, marks: [Mark])? {
        let characters = Array(text)
        let marks = state.marks.filter { $0.time || $0.day }.sorted { $0.range.lowerBound < $1.range.lowerBound }
        func wholly(_ pattern: String, _ gap: String) -> Bool {
            !matches("^[\\s,.;:!-]*(?:\(pattern))[\\s,.;:!-]*$", in: gap).isEmpty
        }
        func between(_ index: Int) -> String? {
            guard marks[index].range.upperBound <= marks[index + 1].range.lowerBound else { return nil }
            return String(characters[marks[index].range.upperBound..<marks[index + 1].range.lowerBound])
        }
        func together(_ index: Int) -> Bool {
            between(index).map { wholly("", $0) } ?? false
        }
        guard marks.count > 1 else { return nil }
        for index in 0..<(marks.count - 1) {
            guard let gap = between(index) else { continue }
            var start = index
            while start > 0, together(start - 1) {
                start -= 1
            }
            var end = index + 1
            while end + 1 < marks.count, together(end) {
                end += 1
            }
            let first = Array(marks[start...index])
            let second = Array(marks[(index + 1)...end])
            let gapRange = marks[index].range.upperBound..<marks[index + 1].range.lowerBound
            let before = String(characters[..<first[0].range.lowerBound])
            let negated = words.negation.flatMap { matches("(?:\($0))[\\s,]*$", in: before).last }.flatMap { span($0, before) }
            if wholly(words.marker, gap) || (negated != nil && wholly(words.contrast, gap)) {
                let time = second.contains { $0.time }
                let day = second.contains { $0.day }
                let taken = first.filter { ($0.time && time) || ($0.day && day) }
                guard !taken.isEmpty else { continue }
                var ranges = taken.map(\.range)
                if let negated {
                    ranges.append(negated)
                }
                return (ranges, gapRange, taken)
            }
            if let negation = words.negation, !matches("^[\\s,]*(?:(?:\(words.contrast)),? )?(?:\(negation)) $", in: gap).isEmpty {
                return (second.map(\.range), gapRange, second)
            }
        }
        return nil
    }

    static let russianCorrection = Correction(marker: "(?:нет|вернее|точнее|то есть|ой|стоп)(?:,? (?:лучше|давай|давай лучше|пусть будет))?", contrast: "(?:а|но)", negation: "не")
    static let ukrainianCorrection = Correction(marker: "(?:ні|вірніше|точніше|тобто|ой|стоп)(?:,? (?:краще|давай|давай краще))?", contrast: "(?:а|але)", negation: "не")
    static let englishCorrection = Correction(marker: "(?:no|nope|i mean|actually|sorry|or rather|rather|wait)(?:,? (?:make it|better|rather))?", contrast: "(?:but|but rather|rather)", negation: "not")
    static let germanCorrection = Correction(marker: "(?:nein|nee|ich meine|besser gesagt|sorry|oder besser|oder lieber|äh|ähm)(?:,? (?:lieber|besser))?", contrast: "(?:sondern|aber)", negation: "nicht")
    static let frenchCorrection = Correction(marker: "(?:non|plutôt|plutot|je veux dire|pardon|enfin|ou plutôt|ou plutot|ou bien)", contrast: "(?:mais|mais plutôt|mais plutot)", negation: "(?:pas|non pas)")
    static let uzbekCorrection = Correction(marker: "(?:yo'q|aniqrog'i|ya'ni|yani|kechirasiz|emas(?:,? balki)?)", contrast: "balki", negation: nil)
    static let arabicCorrection = Correction(marker: "(?:لا|اقصد|اعني|عفوا|بل|لا بل)", contrast: "(?:بل|ولكن|لكن)", negation: "(?:و?ليس|مش|لا)")
}
