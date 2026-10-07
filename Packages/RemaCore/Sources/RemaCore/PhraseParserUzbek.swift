import Foundation

extension PhraseParser {
    private static let uzMonths = "(yanvar|fevral|mart|aprel|may|iyun|iyul|avgust|sentabr|sentyabr|oktabr|oktyabr|noyabr|dekabr)(?:ning|da|ga|dan)?"
    static let uzWeekdays = "(dushanba|seshanba|chorshanba|payshanba|juma|shanba|yakshanba)(?:da|lari|ga)?"
    private static let uzCount = "(\\d+|bir|ikki|uch|to'rt|besh|o'n|o'n besh|yigirma|o'ttiz)"
    private static let uzFillers: Set<String> = ["iltimos", "menga", "kerak"]
    private static let uzDangling: Set<String> = ["eslat", "eslating", "eslatib", "qo'y", "qo'ying", "va", "da", "ga", "ham", "esla"]

    static let uzbekWords: Set<String> = [
        "ertaga", "bugun", "soat", "har", "kuni", "keyin", "eslat", "eslating", "eslatib", "dushanba", "seshanba",
        "chorshanba", "payshanba", "juma", "shanba", "yakshanba", "ertalab", "kechqurun", "oldin", "indinga", "hafta", "yili",
        "ketganimda", "kelganimda", "chiqqanimda", "borganimda", "qaytganimda", "yetganimda",
        "kunora", "tushlikda", "tushlik", "ishdan", "oxirida", "oyning", "ikkinchi", "dam", "olish",
    ]

    static func looksUzbekCyrillic(_ text: String, preferred: String?) -> Bool {
        let lower = text.lowercased()
        if lower.contains(where: { "ўқғҳ".contains($0) }) { return true }
        guard !lower.contains(where: { "ыщі".contains($0) }) else { return false }
        let cyrillic = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
        // These words are Uzbek and never Russian, they settle it even under a Russian interface.
        if cyrillic.contains(where: { ["эртага", "бугун", "индинга", "эрталаб", "соат"].contains($0) }) { return true }
        guard preferred?.hasPrefix("uz") == true else { return false }
        let words = uzbekLatin(lower).0.split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.contains { uzbekWords.contains($0) }
    }

    func parseUzbek(_ input: String) -> ParsedPhrase {
        let (latin, origin) = PhraseParser.uzbekLatin(input)
        let text = latin.lowercased()
        var state = State()

        extras(text, &state, PhraseParser.uzbekExtras, weekday: uzWeekday)
        uzRepeats(text, &state)
        uzOffsets(text, &state)
        uzDates(text, &state)
        uzTimes(text, &state)
        uzAlerts(text, &state)
        uzFlags(text, &state)
        uzPlaces(text, &state)

        let schedule = resolve(&state)
        let used = state.used.compactMap { range -> Range<Int>? in
            guard range.lowerBound < origin.count, range.upperBound - 1 < origin.count, !range.isEmpty else { return nil }
            return origin[range.lowerBound]..<(origin[range.upperBound - 1] + 1)
        }
        return ParsedPhrase(
            title: title(input, used: used, fillers: PhraseParser.uzFillers, dangling: PhraseParser.uzDangling.union(PhraseParser.uzDanglingCyrillic)),
            schedule: schedule,
            preAlerts: Array(Set(state.preAlerts)).sorted(by: >),
            urgent: state.urgent,
            nag: state.nag,
            placeTrigger: state.placeTrigger,
            placeNames: state.placeNames,
            highlights: merge(used),
            hasExplicitTime: state.time != nil || state.exact != nil || state.dayPart != nil,
            alternative: state.alternative
        )
    }

    private static let uzDanglingCyrillic: Set<String> = ["эслат", "эслатинг", "эслатиб", "қўй", "қўйинг", "ва"]

    static func uzbekLatin(_ text: String) -> (String, [Int]) {
        let table: [Character: String] = [
            "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "j", "з": "z", "и": "i",
            "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t",
            "у": "u", "ф": "f", "х": "x", "ц": "ts", "ч": "ch", "ш": "sh", "ъ": "'", "ь": "", "э": "e", "ю": "yu",
            "я": "ya", "ў": "o'", "қ": "q", "ғ": "g'", "ҳ": "h",
        ]
        var output = ""
        var origin: [Int] = []
        for (index, character) in text.enumerated() {
            let lower = character.lowercased().first ?? character
            var piece: String
            if let mapped = table[lower] {
                piece = mapped
                if character.isUppercase, let first = piece.first {
                    piece = String(first).uppercased() + piece.dropFirst()
                }
            } else if "ʻ’‘`ʼ".contains(character) {
                piece = "'"
            } else {
                piece = String(character)
            }
            for symbol in piece {
                output.append(symbol)
                origin.append(index)
            }
        }
        return (output, origin)
    }

    private func uzWeekday(_ word: String) -> Weekday? {
        if word.hasPrefix("dushanba") { return .monday }
        if word.hasPrefix("seshanba") { return .tuesday }
        if word.hasPrefix("chorshanba") { return .wednesday }
        if word.hasPrefix("payshanba") { return .thursday }
        if word.hasPrefix("juma") { return .friday }
        if word.hasPrefix("yakshanba") { return .sunday }
        if word.hasPrefix("shanba") { return .saturday }
        return nil
    }

    private func uzMonth(_ word: String) -> Int? {
        let stems = ["yanv", "fev", "mart", "apr", "may", "iyun", "iyul", "avg", "sent", "okt", "noy", "dek"]
        return stems.firstIndex { word.hasPrefix($0) }.map { $0 + 1 }
    }

    private func uzNumber(_ word: String) -> Int? {
        if let value = Int(word) { return value }
        switch word {
        case "bir": return 1
        case "ikki": return 2
        case "uch": return 3
        case "to'rt": return 4
        case "besh": return 5
        case "o'n": return 10
        case "o'n besh": return 15
        case "yigirma": return 20
        case "o'ttiz": return 30
        default: return nil
        }
    }

    private func uzRepeats(_ text: String, _ state: inout State) {
        take("(har kuni|kundalik|har kun)", text, &state) { _, s in s.rule = .daily; return true }
        take("(ish kunlari|ish kunlarida)", text, &state) { _, s in s.rule = .weekdays; return true }
        take("har (\\d+) kunda", text, &state) { m, s in
            guard let count = group(m, 1, text).flatMap(Int.init), count > 0 else { return false }
            s.rule = count == 1 ? .daily : .everyDays(count)
            return true
        }
        let list = "\(PhraseParser.uzWeekdays)((\\s*(,|va)\\s*)\(PhraseParser.uzWeekdays))*"
        take("har \(list)", text, &state) { m, s in
            guard let whole = Range(m.range, in: text) else { return false }
            let pieces: [String] = String(text[whole]).split(whereSeparator: { !$0.isLetter }).map(String.init)
            let days = pieces.compactMap(self.uzWeekday)
            guard !days.isEmpty else { return false }
            s.weekdays = Array(Set(days)).sorted()
            s.rule = .weekly(s.weekdays)
            return true
        }
        take("(har hafta|haftalik)", text, &state) { _, s in s.rule = .weekly([]); return true }
        take("(har oy|har oyning|oylik)( (\\d{1,2})-?(kuni|sanasi)?)?", text, &state) { m, s in
            s.rule = .monthlyOnDay(group(m, 3, text).flatMap(Int.init) ?? 0)
            return true
        }
        take("(har yili|har yil|yillik)( (\\d{1,2})[ -]\(PhraseParser.uzMonths))?", text, &state) { m, s in
            if let day = group(m, 3, text).flatMap(Int.init), let month = group(m, 4, text).flatMap(self.uzMonth), (1...31).contains(day) {
                s.rule = .yearly(month: month, day: day)
                s.date = nextDate(month: month, day: day, year: nil)
            } else {
                s.rule = .yearly(month: 0, day: 0)
            }
            return true
        }
    }

    private func uzOffsets(_ text: String, _ state: inout State) {
        take("yarim soatdan (?:keyin|so'ng)", text, &state) { _, s in
            s.exact = now.addingTimeInterval(1_800)
            return true
        }
        take("\(PhraseParser.uzCount) (daqiqa|minut|soat|kun|hafta|oy)dan (?:keyin|so'ng)", text, &state) { m, s in
            let unit = group(m, 2, text) ?? ""
            let count = group(m, 1, text).flatMap(uzNumber) ?? 1
            switch unit {
            case "daqiqa", "minut": s.exact = now.addingTimeInterval(Double(count) * 60)
            case "soat": s.exact = now.addingTimeInterval(Double(count) * 3600)
            case "kun": s.dayOffset = count
            case "hafta": s.dayOffset = count * 7
            default:
                if let date = calendar.date(byAdding: .month, value: count, to: now) {
                    s.date = LocalDate(date, in: calendar)
                }
            }
            return true
        }
    }

    private func uzDates(_ text: String, _ state: inout State) {
        take("(indinga|ertadan keyin)", text, &state) { _, s in s.dayOffset = 2; return true }
        take("(ertaga)", text, &state) { _, s in s.dayOffset = 1; return true }
        take("(bugun)", text, &state) { _, s in s.dayOffset = 0; return true }
        take("(\\d{1,2})[ -]\(PhraseParser.uzMonths)(?: (\\d{4}))?", text, &state) { m, s in
            guard let day = group(m, 1, text).flatMap(Int.init), let month = group(m, 2, text).flatMap(self.uzMonth), (1...31).contains(day) else { return false }
            s.date = nextDate(month: month, day: day, year: group(m, 3, text).flatMap(Int.init))
            if case .yearly = s.rule {
                s.rule = .yearly(month: month, day: day)
            }
            return true
        }
        take("(?:kelasi )?\(PhraseParser.uzWeekdays)(?: kuni)?", text, &state) { m, s in
            guard s.rule == nil, let word = group(m, 1, text), let day = self.uzWeekday(word) else { return false }
            s.weekdays = [day]
            return true
        }
    }

    private func uzTimes(_ text: String, _ state: inout State) {
        take("(?:soat )?(\\d{1,2})[:.](\\d{2}) ?(?:da|ga)?", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), let minute = group(m, 2, text).flatMap(Int.init), hour < 24, minute < 60 else { return false }
            s.time = LocalTime(hour: hour, minute: minute)
            return true
        }
        take("soat (\\d{1,2}) ?(?:da|ga)?", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), hour < 24 else { return false }
            s.time = LocalTime(hour: hour, minute: 0)
            return true
        }
        take("(tushda|tush paytida)", text, &state) { _, s in s.time = LocalTime(hour: 12, minute: 0); return true }
        take("(yarim tunda)", text, &state) { _, s in s.time = LocalTime(hour: 0, minute: 0); return true }
        take("(ertalab|tongda)", text, &state) { _, s in s.dayPart = morning; return true }
        take("(kunduzi)", text, &state) { _, s in s.dayPart = LocalTime(hour: 13, minute: 0); return true }
        take("(kechqurun|kechki payt|kechda)", text, &state) { _, s in s.dayPart = evening; return true }
        take("(kechasi|tunda)", text, &state) { _, s in s.dayPart = LocalTime(hour: 23, minute: 0); return true }
    }

    private func uzAlerts(_ text: String, _ state: inout State) {
        take("yarim soat oldin", text, &state) { _, s in s.preAlerts.append(30); return true }
        take("\(PhraseParser.uzCount) (daqiqa|minut|soat|kun|hafta) oldin", text, &state) { m, s in
            let unit = group(m, 2, text) ?? ""
            let count = group(m, 1, text).flatMap(uzNumber) ?? 1
            switch unit {
            case "daqiqa", "minut": s.preAlerts.append(count)
            case "soat": s.preAlerts.append(count * 60)
            case "kun": s.preAlerts.append(count * 1_440)
            default: s.preAlerts.append(count * 10_080)
            }
            return true
        }
        take("oldindan", text, &state) { _, _ in true }
    }

    private func uzFlags(_ text: String, _ state: inout State) {
        take("(shoshilinch|muhim|zudlik bilan)", text, &state) { _, s in s.urgent = true; return true }
        take("(takror-takror|belgilagunimcha|bajarmagunimcha)", text, &state) { _, s in s.nag = true; return true }
    }

    private func uzPlaces(_ text: String, _ state: inout State) {
        guard !places.isEmpty else { return }
        take("([\\p{L}']+)(dan|ga|da) (ketganimda|chiqqanimda|kelganimda|borganimda|qaytganimda|yetganimda|yetib kelganimda)", text, &state) { m, s in
            guard let stem = group(m, 1, text), let suffix = group(m, 2, text), let verb = group(m, 3, text) else { return false }
            guard let place = places.first(where: { PhraseParser.uzbekLatin($0).0.lowercased() == stem }) else { return false }
            let leaving = verb.hasPrefix("ket") || verb.hasPrefix("chiq") || suffix == "dan"
            s.placeTrigger = leaving ? .leave : .arrive
            s.placeNames = [place]
            return true
        }
    }
}
