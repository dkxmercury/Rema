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
        var current = text
        while removed.count < 3, let next = takenBack(in: current, state, words) {
            removed.append(next)
            var characters = Array(text)
            for range in removed {
                for index in range where index < characters.count {
                    characters[index] = " "
                }
            }
            current = String(characters)
            state = State()
            state.used = removed
            pass(current, &state)
        }
        return state
    }

    private func takenBack(in text: String, _ state: State, _ words: Correction) -> Range<Int>? {
        let characters = Array(text)
        let marks = state.marks.sorted { $0.range.lowerBound < $1.range.lowerBound }
        func wholly(_ pattern: String, _ gap: String) -> Bool {
            !matches("^[\\s,.;:!-]*(?:\(pattern))[\\s,.;:!-]*$", in: gap).isEmpty
        }
        for (first, second) in zip(marks, marks.dropFirst()) where first.range.upperBound <= second.range.lowerBound && ((first.time && second.time) || (first.day && second.day)) {
            let gap = String(characters[first.range.upperBound..<second.range.lowerBound])
            let before = String(characters[..<first.range.lowerBound])
            let negated = words.negation.flatMap { matches("(?:\($0))[\\s,]*$", in: before).last }.flatMap { span($0, before) }
            if wholly(words.marker, gap) || (negated != nil && wholly(words.contrast, gap)) {
                return (negated?.lowerBound ?? first.range.lowerBound)..<second.range.lowerBound
            }
            if let negation = words.negation, !matches("^[\\s,]*(?:(?:\(words.contrast)),? )?(?:\(negation)) $", in: gap).isEmpty {
                return first.range.upperBound..<second.range.upperBound
            }
        }
        return nil
    }

    static let russianCorrection = Correction(marker: "(?:нет|вернее|точнее|то есть|ой|стоп)(?:,? (?:лучше|давай|давай лучше|пусть будет))?", contrast: "(?:а|но)", negation: "не")
    static let ukrainianCorrection = Correction(marker: "(?:ні|вірніше|точніше|тобто|ой|стоп)(?:,? (?:краще|давай|давай краще))?", contrast: "(?:а|але)", negation: "не")
    static let englishCorrection = Correction(marker: "(?:no|nope|i mean|actually|sorry|or rather|rather|wait)(?:,? (?:make it|better|rather))?", contrast: "(?:but|but rather|rather)", negation: "not")
    static let germanCorrection = Correction(marker: "(?:nein|nee|ich meine|besser gesagt|sorry|oder besser|oder lieber|äh|ähm)(?:,? (?:lieber|besser))?", contrast: "(?:sondern|aber)", negation: "nicht")
    static let frenchCorrection = Correction(marker: "(?:non|plutôt|plutot|je veux dire|pardon|enfin|ou plutôt|ou plutot|ou bien)", contrast: "(?:mais|mais plutôt|mais plutot|et)", negation: "(?:pas|non pas)")
    static let uzbekCorrection = Correction(marker: "(?:yo'q|aniqrog'i|ya'ni|yani|kechirasiz|emas(?:,? balki)?)", contrast: "balki", negation: nil)
    static let arabicCorrection = Correction(marker: "(?:لا|اقصد|اعني|عفوا|بل|لا بل)", contrast: "(?:بل|ولكن|لكن)", negation: "(?:و?ليس|مش|لا)")
}
