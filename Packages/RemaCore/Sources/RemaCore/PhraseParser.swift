import Foundation

public struct ParsedPhrase: Equatable, Sendable {
    public var title: String
    public var schedule: Schedule?
    public var preAlerts: [Int]
    public var urgent: Bool
    public var nag: Bool
    public var placeTrigger: PlaceTrigger?
    public var placeNames: [String]
    public var highlights: [Range<Int>]
    public var hasExplicitTime: Bool
    public var alternative: Schedule? = nil
    public var hasExplicitDay = false
    public var corrected = false
    public var usedPart: LocalTime? = nil
}

// The field reparses the phrase on every keystroke, and compiling a pattern costs far more than matching it.
final class PatternCache: @unchecked Sendable {
    static let shared = PatternCache()
    private let lock = NSLock()
    private var compiled: [String: NSRegularExpression] = [:]

    func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let regex = compiled[pattern] {
            return regex
        }
        let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\d])(?:" + pattern + ")(?![\\p{L}\\d])", options: [.caseInsensitive])
        compiled[pattern] = regex
        return regex
    }
}

public struct PhraseParser {
    public let now: Date
    public let calendar: Calendar
    public let morning: LocalTime
    public let evening: LocalTime
    public let places: [String]
    public let preferred: String?
    public var coordinate: Coordinate?
    public var synonyms: [String: String] = [:]
    public var languageSynonyms: [String: [String: String]] = [:]
    // A later part of a phrase whose day was named in an earlier one, «завтра в 3 …, в 5 …».
    var dayNamedBefore = false

    public init(now: Date, calendar: Calendar, morning: LocalTime, evening: LocalTime, places: [String] = [], preferred: String? = nil) {
        self.now = now
        self.calendar = calendar
        self.morning = morning
        self.evening = evening
        self.places = places
        self.preferred = preferred
    }

    private static let months = ["январ", "феврал", "март", "апрел", "ма", "июн", "июл", "август", "сентябр", "октябр", "ноябр", "декабр"]
    static let monthPattern = "(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря)"
    static let weekdayPattern = "(понедельник\\w*|пн|вторник\\w*|(?<!\\d )вт|сред(?:а|у|ы|ой|е|ам|ами|ах)|ср|четверг\\w*|чт|пятниц\\w*|пт|суббот\\w*|сб|воскресень\\w*|вс)"
    private static let fillers: Set<String> = ["напомни", "напомните", "напомнить", "мне", "пожалуйста", "надо", "нужно"]
    private static let dangling: Set<String> = ["и", "а", "в", "во", "на", "с", "со", "к", "по"]
    // A number before a noun is an amount, «около 5 км», «в 2 раза», «в 5 подъезде», and so is a list of them, «в 5 и 6 классах».
    static let ruCountedNouns = "(?:(?:км|кг|г|м|л|см|мм|мл|сум|лет|пик|ряд|ряду|ряда|раз|раза|людей|люди|места|мест|место|год|года|гостей|гостя|гости)(?![\\p{L}])|(?:человек|штук|процент|рубл|доллар|евро|подъезд|числ|этаж|класс|кабинет|квартир|корпус|вагон|автобус|маршрут|школ|групп|палат|минут|секунд|недел|месяц|друз)\\w*)"
    static let ruCounted = "(?!(?:(?:,| и) \\d{1,2})* \(ruCountedNouns))"
    static let ruNoMonth = "(?!(?:(?:,| и) \\d{1,2})* \(monthPattern))"
    static let conjunctions: Set<String> = ["и", "а", "і", "й", "та", "and", "und", "et", "va", "ва", "و"]

    struct State {
        var used: [Range<Int>] = []
        var date: LocalDate?
        var dayOffset: Int?
        var time: LocalTime?
        var exact: Date?
        var dayPart: LocalTime?
        var rule: RepeatRule?
        var weekdays: [Weekday] = []
        var preAlerts: [Int] = []
        var urgent = false
        var nag = false
        var placeTrigger: PlaceTrigger?
        var placeNames: [String] = []
        var meridiem = false
        var alternative: Schedule?
        var marks: [Mark] = []
        var nextWeek = false
        var corrected = false
        var end = RepeatEnd.never
        var span: Int?
        var deadline = false
        var sun: SunEvent?
        var holiday: LocalDate?
        var holidayRange: Range<Int>?
    }

    struct Mark {
        var range: Range<Int>
        var time: Bool
        var day: Bool
        var clock: LocalTime?
        var meridiem = false
    }

    public func parse(_ input: String) -> ParsedPhrase {
        // The server's words of the language the phrase is in, so a word of one language never rewrites another.
        let table = PhraseParser.synonymKeys(input).reduce(synonyms) { found, key in
            found.merging(languageSynonyms[key] ?? [:]) { first, _ in first }
        }
        guard !table.isEmpty, let (rewritten, origin) = PhraseParser.rewrite(input, table) else {
            return parseDirect(input)
        }
        var parsed = parseDirect(rewritten)
        parsed.highlights = parsed.highlights.compactMap { range -> Range<Int>? in
            guard !range.isEmpty, range.upperBound - 1 < origin.count else { return nil }
            return origin[range.lowerBound]..<(origin[range.upperBound - 1] + 1)
        }
        // A word that stays in the title is kept as typed, «позвонить мамке» does not turn into «маме».
        for (variant, meaning) in table {
            parsed.title = PhraseParser.restore(parsed.title, meaning: meaning, typed: variant, in: input)
        }
        return parsed
    }

    static func synonymKeys(_ input: String) -> [String] {
        if looksArabic(input) {
            return ["ar"]
        }
        if mostlyLatin(input) {
            if transliterated(input) != nil {
                return ["ru"]
            }
            let code = latinLanguage(input, preferred: nil)
            return code == "uz" ? ["uz-Latn", "uz"] : [code]
        }
        if looksUzbekCyrillic(input, preferred: nil) {
            return ["uz-Cyrl", "uz", "ru"]
        }
        if looksUkrainian(input, preferred: nil) {
            return ["uk", "ru"]
        }
        return ["ru"]
    }

    static func restore(_ title: String, meaning: String, typed variant: String, in input: String) -> String {
        guard let typed = input.range(of: "(?<![\\p{L}])" + NSRegularExpression.escapedPattern(for: variant) + "(?![\\p{L}])", options: [.regularExpression, .caseInsensitive]),
              let found = title.range(of: "(?<![\\p{L}])" + NSRegularExpression.escapedPattern(for: meaning) + "(?![\\p{L}])", options: [.regularExpression, .caseInsensitive]) else { return title }
        var word = String(input[typed])
        if found.lowerBound == title.startIndex {
            word = word.prefix(1).uppercased() + word.dropFirst()
        }
        return title.replacingCharacters(in: found, with: word)
    }

    // Whole words only; each new letter points back into the typed text, so highlights land on what was typed.
    static func rewrite(_ input: String, _ synonyms: [String: String]) -> (String, [Int])? {
        let characters = Array(input)
        var output = ""
        var origin: [Int] = []
        var changed = false
        var index = 0
        while index < characters.count {
            guard characters[index].isLetter else {
                output.append(characters[index])
                origin.append(index)
                index += 1
                continue
            }
            var end = index
            while end < characters.count, characters[end].isLetter || characters[end] == "'" {
                end += 1
            }
            let word = String(characters[index..<end])
            if let replacement = synonyms[word.lowercased()], !replacement.isEmpty {
                let length = end - index
                for (offset, symbol) in replacement.enumerated() {
                    output.append(symbol)
                    origin.append(index + (offset == replacement.count - 1 ? length - 1 : min(offset, length - 1)))
                }
                changed = true
            } else {
                for offset in index..<end {
                    output.append(characters[offset])
                    origin.append(offset)
                }
            }
            index = end
        }
        return changed ? (output, origin) : nil
    }

    func parseDirect(_ input: String) -> ParsedPhrase {
        if PhraseParser.looksArabic(input) {
            return parseArabic(input)
        }
        if PhraseParser.mostlyLatin(input) {
            if let (cyrillic, origin) = PhraseParser.transliterated(input) {
                if let (fixed, back) = PhraseParser.rewrite(cyrillic, PhraseParser.translitFixes) {
                    return parseRussian(fixed, typed: input, origin: back.map { origin[$0] })
                }
                return parseRussian(cyrillic, typed: input, origin: origin)
            }
            switch PhraseParser.latinLanguage(input, preferred: preferred) {
            case "de": return parseGerman(input)
            case "fr": return parseFrench(input)
            case "uz": return parseUzbek(input)
            default: return parseEnglish(input)
            }
        }
        if PhraseParser.looksUzbekCyrillic(input, preferred: preferred) {
            return better(parseUzbek(input), than: parseRussian(input))
        }
        if PhraseParser.looksUkrainian(input, preferred: preferred) {
            return better(parseUkrainian(input), than: parseRussian(input))
        }
        return parseRussian(input)
    }

    // One Ukrainian or Uzbek letter in a name does not make the phrase Ukrainian or Uzbek: the reading that understands more wins.
    private func better(_ detected: ParsedPhrase, than russian: ParsedPhrase) -> ParsedPhrase {
        func score(_ parsed: ParsedPhrase) -> Int {
            (parsed.schedule != nil ? 1000 : 0) + parsed.highlights.reduce(0) { $0 + $1.count }
        }
        return score(russian) > score(detected) ? russian : detected
    }

    // Typed in Latin letters, Russian comes back with spellings the rules do not know.
    static let translitFixes: [String: String] = [
        "понеделник": "понедельник", "понеделника": "понедельника", "каждий": "каждый", "каждыи": "каждый", "каждии": "каждый",
        "воскресеные": "воскресенье", "воскресение": "воскресенье", "воскресене": "воскресенье", "ночю": "ночью",
        "севодня": "сегодня", "сиводня": "сегодня", "сегодна": "сегодня", "ден": "день",
    ]

    func parseRussian(_ input: String, typed: String? = nil, origin: [Int]? = nil) -> ParsedPhrase {
        let text = input.lowercased().replacingOccurrences(of: "ё", with: "е")
        func pass(_ text: String, _ state: inout State) {
            extras(text, &state, PhraseParser.russianExtras, weekday: weekday)
            repeats(text, &state)
            limits(text, &state, PhraseParser.russianLimits, weekday: weekday, month: month)
            offsets(text, &state)
            dates(text, &state)
            times(text, &state)
            alerts(text, &state)
            flags(text, &state)
            placeRules(text, &state)
        }
        var state = corrected(text, PhraseParser.russianCorrection, pass)

        let schedule = resolve(&state)
        // A Latin pair like «yu» gives one Cyrillic letter, so a range ends where the next letter begins.
        let used = origin.map { origin in
            state.used.compactMap { range -> Range<Int>? in
                guard !range.isEmpty, range.upperBound - 1 < origin.count else { return nil }
                let next = range.upperBound < origin.count ? origin[range.upperBound] : (typed ?? input).count
                return origin[range.lowerBound]..<max(origin[range.upperBound - 1] + 1, next)
            }
        } ?? state.used
        return ParsedPhrase(
            title: title(typed ?? input, used: used, fillers: PhraseParser.fillers, dangling: PhraseParser.dangling),
            schedule: schedule,
            preAlerts: Array(Set(state.preAlerts)).sorted(by: >),
            urgent: state.urgent,
            nag: state.nag,
            placeTrigger: state.placeTrigger,
            placeNames: state.placeNames,
            highlights: merge(used),
            hasExplicitTime: state.time != nil || state.exact != nil || state.dayPart != nil,
            alternative: state.alternative,
            hasExplicitDay: state.date != nil || state.dayOffset != nil || !state.weekdays.isEmpty || state.rule != nil || state.exact != nil,
            corrected: state.corrected,
            usedPart: state.time == nil && state.exact == nil ? state.dayPart : nil
        )
    }

    func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = PatternCache.shared.regex(pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    func group(_ match: NSTextCheckingResult, _ index: Int, _ text: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    func span(_ match: NSTextCheckingResult, _ text: String) -> Range<Int>? {
        guard let range = Range(match.range, in: text) else { return nil }
        let lower = text.distance(from: text.startIndex, to: range.lowerBound)
        return lower..<(lower + text.distance(from: range.lowerBound, to: range.upperBound))
    }

    func saysNext(_ match: NSTextCheckingResult, _ text: String) -> Bool {
        guard let range = Range(match.range, in: text) else { return false }
        let words = text[range]
        return ["следующ", "наступн", "next ", "nächsten", "prochain"].contains { words.contains($0) }
    }

    func isFree(_ range: Range<Int>, _ state: State) -> Bool {
        !state.used.contains { $0.overlaps(range) }
    }

    func take(_ pattern: String, _ text: String, _ state: inout State, _ apply: (NSTextCheckingResult, inout State) -> Bool) {
        for match in matches(pattern, in: text) {
            guard let range = span(match, text), isFree(range, state) else { continue }
            let before = state
            if apply(match, &state) {
                state.used.append(range)
                let time = state.time != before.time || state.dayPart != before.dayPart || state.exact != before.exact
                let day = state.date != before.date || state.dayOffset != before.dayOffset || state.weekdays != before.weekdays || state.rule != before.rule || state.exact != before.exact
                state.marks.append(Mark(range: range, time: time, day: day, clock: time ? state.time : nil, meridiem: state.meridiem))
            }
        }
    }

    // «В тестовой среде», «окружающая среда»: the word is a weekday only in the forms and with the words a day takes.
    private func wednesday(_ word: String, _ match: NSTextCheckingResult, _ text: String) -> Bool {
        guard word.hasPrefix("сред"), let range = Range(match.range, in: text) else { return true }
        let whole = String(text[range])
        let before = text[..<range.lowerBound].split(separator: " ").last.map(String.init) ?? ""
        switch word {
        case "среду":
            return whole.hasPrefix("в ") || whole.hasPrefix("во ") || whole != word || ["на", "через", "за", "каждую", "эту", "следующую", "ближайшую", "прошлую", "про", "и", "или"].contains(before) || before.hasSuffix(",") || before.isEmpty
        case "среды":
            return ["до", "с", "со", "после", "от", "для", "каждой", "кроме", "к"].contains(before)
        case "среде":
            return !whole.hasPrefix("в") && ["к", "по"].contains(before)
        case "среда":
            return whole != word || before.isEmpty || ["эта", "следующая", "каждая", "ближайшая"].contains(before)
        case "средам":
            return before == "по"
        default:
            return false
        }
    }

    private func weekday(_ word: String) -> Weekday? {
        if word.hasPrefix("пн") || word.hasPrefix("понед") { return .monday }
        if word.hasPrefix("вт") { return .tuesday }
        if word.hasPrefix("ср") { return .wednesday }
        if word.hasPrefix("чт") || word.hasPrefix("четв") { return .thursday }
        if word.hasPrefix("пт") || word.hasPrefix("пятн") { return .friday }
        if word.hasPrefix("сб") || word.hasPrefix("субб") { return .saturday }
        if word.hasPrefix("вс") || word.hasPrefix("воскр") { return .sunday }
        return nil
    }

    private func month(_ word: String) -> Int? {
        if word.hasPrefix("мая") { return 5 }
        if word.hasPrefix("мар") { return 3 }
        return PhraseParser.months.firstIndex { $0 != "ма" && word.hasPrefix($0) }.map { $0 + 1 }
    }

    private func number(_ word: String) -> Int? {
        if let value = Int(word) { return value }
        switch word {
        case "одну", "один", "одна", "минуту", "час", "день", "неделю", "месяц": return 1
        case "пару", "два", "две": return 2
        case "шесть": return 6
        case "семь": return 7
        case "восемь": return 8
        case "девять": return 9
        case "десять": return 10
        case "пятнадцать": return 15
        case "двадцать": return 20
        case "тридцать": return 30
        case "сорок": return 40
        case "сорок пять": return 45
        case "пятьдесят": return 50
        case "три": return 3
        case "четыре": return 4
        case "пять": return 5
        default: return nil
        }
    }

    private func repeats(_ text: String, _ state: inout State) {
        take("(каждое утро|по утрам)", text, &state) { _, s in s.rule = .daily; s.dayPart = morning; return true }
        take("(каждый вечер|по вечерам)", text, &state) { _, s in s.rule = .daily; s.dayPart = evening; return true }
        take("(каждую ночь)", text, &state) { _, s in s.rule = .daily; s.dayPart = LocalTime(hour: 23, minute: 0); return true }
        take("(каждый день|ежедневно)", text, &state) { _, s in s.rule = .daily; return true }
        take("(по будним дням|по будням|каждый будний день|по рабочим дням)", text, &state) { _, s in s.rule = .weekdays; return true }
        take("каждые (\\d{1,4}) (дня|дней)", text, &state) { m, s in
            guard let count = group(m, 1, text).flatMap(Int.init), count > 0 else { return false }
            s.rule = count == 1 ? .daily : .everyDays(count)
            return true
        }
        let list = "\(PhraseParser.weekdayPattern)((\\s*(,|и)\\s*)\(PhraseParser.weekdayPattern))*"
        take("(?<!(?:понедельника|вторника|среды|четверга|пятницы|субботы|воскресенья) )(каждый|каждую|каждое|по) \(list)", text, &state) { m, s in
            guard let whole = Range(m.range, in: text) else { return false }
            let words = text[whole].split { !$0.isLetter }.map(String.init)
            let days = words.compactMap(self.weekday)
            guard !days.isEmpty else { return false }
            s.weekdays = Array(Set(days)).sorted()
            s.rule = .weekly(s.weekdays)
            return true
        }
        take("(каждую неделю|еженедельно)", text, &state) { _, s in s.rule = .weekly([]); return true }
        take("каждое (\\d{1,2})(-?е|-?го)? число", text, &state) { m, s in
            guard let day = group(m, 1, text).flatMap(Int.init), (1...31).contains(day) else { return false }
            s.rule = .monthlyOnDay(day)
            return true
        }
        take("(каждый месяц|ежемесячно)( (\\d{1,2})(-?го|-?е)?( числа)?)?", text, &state) { m, s in
            let day = group(m, 3, text).flatMap(Int.init) ?? 0
            s.rule = .monthlyOnDay(day)
            return true
        }
        take("(каждый год|ежегодно)( (\\d{1,2}) \(PhraseParser.monthPattern))?", text, &state) { m, s in
            if let day = group(m, 3, text).flatMap(Int.init), let month = group(m, 4, text).flatMap(self.month) {
                s.rule = .yearly(month: month, day: day)
                s.date = nextDate(month: month, day: day, year: nil)
            } else {
                s.rule = .yearly(month: 0, day: 0)
            }
            return true
        }
    }

    private func offsets(_ text: String, _ state: inout State) {
        take("через (полчаса|полтора часа)", text, &state) { m, s in
            let minutes = group(m, 1, text) == "полчаса" ? 30 : 90
            s.exact = now.addingTimeInterval(Double(minutes) * 60)
            return true
        }
        take("через (\\d{1,2})[,.]5 час\\w*", text, &state) { m, s in
            guard let hours = group(m, 1, text).flatMap(Int.init) else { return false }
            s.exact = now.addingTimeInterval(Double(hours * 60 + 30) * 60)
            return true
        }
        take("через (?:(\\d{1,4}|одну|один|пару|два|две|три|четыре|пять|шесть|семь|восемь|девять|десять|пятнадцать|двадцать|тридцать|сорок пять|сорок|пятьдесят) )?(минуту|минуты|минут|час|часа|часов|день|дня|дней|неделю|недели|недель|месяц|месяца|месяцев)", text, &state) { m, s in
            let unit = group(m, 2, text) ?? ""
            let count = group(m, 1, text).flatMap(number) ?? 1
            if unit.hasPrefix("минут") {
                s.exact = now.addingTimeInterval(Double(count) * 60)
            } else if unit.hasPrefix("час") {
                s.exact = now.addingTimeInterval(Double(count) * 3600)
            } else if unit.hasPrefix("д") {
                s.dayOffset = count
            } else if unit.hasPrefix("недел") {
                s.dayOffset = count * 7
            } else {
                if let date = calendar.date(byAdding: .month, value: count, to: now) {
                    s.date = LocalDate(date, in: calendar)
                }
            }
            return true
        }
    }

    private func dates(_ text: String, _ state: inout State) {
        take("(сегодня|седня|сення)", text, &state) { _, s in s.dayOffset = 0; return true }
        take("(послезавтра)", text, &state) { _, s in s.dayOffset = 2; return true }
        take("(завтра|завтро|зовтра|завтр)", text, &state) { _, s in s.dayOffset = 1; return true }
        // «В 10 и 11 ноября» starts on the first day.
        take("(?:в |с )?(\\d{1,2})(?:(?:,| и) \\d{1,2})+ \(PhraseParser.monthPattern)", text, &state) { m, s in
            guard let day = group(m, 1, text).flatMap(Int.init), let month = group(m, 2, text).flatMap(self.month), (1...31).contains(day) else { return false }
            s.date = nextDate(month: month, day: day, year: nil)
            return true
        }
        take("(\\d{1,2}) \(PhraseParser.monthPattern)( (\\d{4}))?", text, &state) { m, s in
            guard let day = group(m, 1, text).flatMap(Int.init), let month = group(m, 2, text).flatMap(self.month), (1...31).contains(day) else { return false }
            let year = group(m, 4, text).flatMap(Int.init)
            s.date = nextDate(month: month, day: day, year: year)
            if case .yearly = s.rule {
                s.rule = .yearly(month: month, day: day)
            }
            return true
        }
        // «15.10» without «в» before it is a date written with a dot.
        take("(?<!(?:в|к|с|до|около|после) )(\\d{1,2})\\.(\\d{1,2})(?:\\.(\\d{4}))?(?![.:]?\\d)", text, &state) { m, s in
            guard let day = group(m, 1, text).flatMap(Int.init), let month = group(m, 2, text).flatMap(Int.init), (1...12).contains(month), (1...LocalDate.days(in: month, year: 2028)).contains(day) else { return false }
            s.date = nextDate(month: month, day: day, year: group(m, 3, text).flatMap(Int.init))
            return true
        }
        take("(?:к|до|на) (\\d{1,2})(?:-?(?:му|е|го))? числ\\w*", text, &state) { m, s in
            guard let day = group(m, 1, text).flatMap(Int.init), (1...31).contains(day) else { return false }
            let today = LocalDate(now, in: calendar)
            var candidate = LocalDate(year: today.year, month: today.month, day: min(day, LocalDate.days(in: today.month, year: today.year)))
            if candidate < today {
                let next = today.month == 12 ? (today.year + 1, 1) : (today.year, today.month + 1)
                candidate = LocalDate(year: next.0, month: next.1, day: min(day, LocalDate.days(in: next.1, year: next.0)))
            }
            s.date = candidate
            return true
        }
        take("(?:в |во )?(следующ\\w+ |эт\\w+ )?\(PhraseParser.weekdayPattern)", text, &state) { m, s in
            guard s.rule == nil || s.rule == .weekly([]), let word = group(m, 2, text), let day = self.weekday(word), wednesday(word, m, text) else { return false }
            s.weekdays = [day]
            s.nextWeek = saysNext(m, text)
            if s.rule == .weekly([]) {
                s.rule = .weekly([day])
            }
            return true
        }
    }

    private func times(_ text: String, _ state: inout State) {
        let modifier = "( утра| вечера| дня| ночи)?"
        let hourWord = "(час|один|два|три|четыре|пять|шесть|семь|восемь|девять|десять|одиннадцать|двенадцать)"
        let ordinal = "(первого|второго|третьего|четвертого|пятого|шестого|седьмого|восьмого|девятого|десятого|одиннадцатого|двенадцатого)"
        let around = "(одного|одному|двух|двум|трех|трем|четырех|четырем|пяти|шести|семи|восьми|девяти|десяти|одиннадцати|двенадцати)"
        let counted = PhraseParser.ruCounted
        let noMonth = PhraseParser.ruNoMonth
        take("(?:около|в районе|ближе к|примерно к|часам к|часикам к) (?:(\\d{1,2})(?:[:.](\\d{2}))?|\(around))(?: час\\w*)?\(modifier)\(noMonth)\(counted)", text, &state) { m, s in
            russianClock(group(m, 1, text).flatMap(Int.init) ?? group(m, 3, text).flatMap(PhraseParser.ruHourCase), minute: group(m, 2, text), group(m, 4, text), &s)
        }
        take("(?:примерно|приблизительно|где-то|где то|часов|часиков) (?:в|к) (?:(\\d{1,2})(?:[:.](\\d{2}))?|\(hourWord))(?: час\\w*)?\(modifier)\(noMonth)\(counted)", text, &state) { m, s in
            russianClock(group(m, 1, text).flatMap(Int.init) ?? group(m, 3, text).flatMap(PhraseParser.ruHour), minute: group(m, 2, text), group(m, 4, text), &s)
        }
        take("(?:между|с) (\\d{1,2})(?:[:.](\\d{2}))? (?:и|до) \\d{1,2}(?:[:.]\\d{2})?(?: час\\w*)?\(modifier)(?! \(PhraseParser.monthPattern))", text, &state) { m, s in
            russianClock(group(m, 1, text).flatMap(Int.init), minute: group(m, 2, text), group(m, 3, text), &s)
        }
        take("(?:в |с )?(\\d{1,2})[:.](\\d{2}) ?[-–] ?\\d{1,2}[:.]\\d{2}\(modifier)", text, &state) { m, s in
            russianClock(group(m, 1, text).flatMap(Int.init), minute: group(m, 2, text), group(m, 3, text), &s)
        }
        take("(?:в |к )?(\\d{1,2})[:.](\\d{2})\(modifier)", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), let minute = group(m, 2, text).flatMap(Int.init), hour < 24, minute < 60 else { return false }
            s.time = LocalTime(hour: adjust(hour, group(m, 3, text)), minute: minute)
            s.meridiem = group(m, 3, text) != nil || PhraseParser.twentyFour(group(m, 1, text))
            return true
        }
        take("(?:в |к )?(\\d{1,2})-(00|15|30|45)\(modifier)", text, &state) { m, s in
            russianClock(group(m, 1, text).flatMap(Int.init), minute: group(m, 2, text), group(m, 3, text), &s)
        }
        take("(?:в|к) (\\d{1,2})(?: час\\w*)?\(modifier)\(noMonth)\(counted)", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), hour < 24 else { return false }
            s.time = LocalTime(hour: adjust(hour, group(m, 2, text)), minute: 0)
            s.meridiem = group(m, 2, text) != nil
            return true
        }
        take("(?:в |к )?(?:пол[ -]?|половин[аеуы] )\(ordinal)\(modifier)", text, &state) { m, s in
            guard let next = group(m, 1, text).flatMap(PhraseParser.ruOrdinal) else { return false }
            s.time = LocalTime(hour: adjust(next == 1 ? 12 : next - 1, group(m, 2, text)), minute: 30)
            s.meridiem = group(m, 2, text) != nil
            return true
        }
        take("(?:в |к )?четверть \(ordinal)\(modifier)", text, &state) { m, s in
            guard let next = group(m, 1, text).flatMap(PhraseParser.ruOrdinal) else { return false }
            s.time = LocalTime(hour: adjust(next == 1 ? 12 : next - 1, group(m, 2, text)), minute: 15)
            s.meridiem = group(m, 2, text) != nil
            return true
        }
        take("(?:в |к )?без (четверти|пяти|десяти|пятнадцати|двадцати пяти|двадцати|\\d{1,2}) \(hourWord)\(modifier)", text, &state) { m, s in
            let before: Int?
            switch group(m, 1, text) {
            case "четверти", "пятнадцати": before = 15
            case "пяти": before = 5
            case "десяти": before = 10
            case "двадцати": before = 20
            case "двадцати пяти": before = 25
            default: before = group(m, 1, text).flatMap(Int.init)
            }
            guard let before, (1..<60).contains(before), let next = group(m, 2, text).flatMap(PhraseParser.ruHour) else { return false }
            s.time = LocalTime(hour: adjust(next == 1 ? 12 : next - 1, group(m, 3, text)), minute: 60 - before)
            s.meridiem = group(m, 3, text) != nil
            return true
        }
        let minutes = "(десять|одиннадцать|двенадцать|тринадцать|четырнадцать|пятнадцать|шестнадцать|семнадцать|восемнадцать|девятнадцать|(?:двадцать|тридцать|сорок|пятьдесят)(?: (?:одна|одну|две|три|четыре|пять|шесть|семь|восемь|девять))?)"
        take("(?:в|к) \(hourWord)(?: \(minutes))?(?: час\\w*)?\(modifier)\(counted)", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(PhraseParser.ruHour) else { return false }
            let minute = group(m, 2, text).map(PhraseParser.ruMinutes) ?? 0
            s.time = LocalTime(hour: adjust(hour, group(m, 3, text)), minute: minute)
            s.meridiem = group(m, 3, text) != nil
            return true
        }
        take("к (часу|двум|трем|четырем|пяти|шести|семи|восьми|девяти|десяти|одиннадцати|двенадцати)(?: час\\w*)?\(modifier)(?! \\p{L}+(?:ам|ям))", text, &state) { m, s in
            russianClock(group(m, 1, text).flatMap(PhraseParser.ruHourCase), minute: nil, group(m, 2, text), &s)
        }
        take("(\\d{1,2}) (утра|вечера|ночи)", text, &state) { m, s in
            russianClock(group(m, 1, text).flatMap(Int.init), minute: nil, " " + (group(m, 2, text) ?? ""), &s)
        }
        take("в полдень", text, &state) { _, s in s.time = LocalTime(hour: 12, minute: 0); return true }
        take("в полночь", text, &state) { _, s in s.time = LocalTime(hour: 0, minute: 0); return true }
        take("(утром|утречком|с утра пораньше)", text, &state) { _, s in s.dayPart = morning; return true }
        take("((?<!с )(?<!со )днем)", text, &state) { _, s in s.dayPart = LocalTime(hour: 13, minute: 0); return true }
        take("(вечером|вечерком|вечерочком)", text, &state) { _, s in s.dayPart = evening; return true }
        take("(ночью)", text, &state) { _, s in s.dayPart = LocalTime(hour: 23, minute: 0); return true }
    }

    // «Без пяти девять», «quarter to nine» and «halb neun» count back from the named hour.
    static func clock(_ hour: Int, minute: Int, before: Bool) -> LocalTime? {
        if before {
            guard (1...24).contains(hour), (1..<60).contains(minute) else { return nil }
            return LocalTime(hour: hour == 1 ? 12 : hour - 1, minute: 60 - minute)
        }
        guard (0...23).contains(hour), (0..<60).contains(minute) else { return nil }
        return LocalTime(hour: hour, minute: minute)
    }

    // «07:30» is written on a 24-hour clock, it never means the evening.
    static func twentyFour(_ hour: String?) -> Bool {
        guard let hour else { return false }
        return hour.count == 2 && hour.hasPrefix("0")
    }

    static func ruHour(_ word: String) -> Int? {
        ["час": 1, "один": 1, "два": 2, "три": 3, "четыре": 4, "пять": 5, "шесть": 6, "семь": 7, "восемь": 8, "девять": 9, "десять": 10, "одиннадцать": 11, "двенадцать": 12][word]
    }

    static func ruOrdinal(_ word: String) -> Int? {
        ["первого": 1, "второго": 2, "третьего": 3, "четвертого": 4, "пятого": 5, "шестого": 6, "седьмого": 7, "восьмого": 8, "девятого": 9, "десятого": 10, "одиннадцатого": 11, "двенадцатого": 12][word]
    }

    static func ruHourCase(_ word: String) -> Int? {
        ["часа": 1, "часу": 1, "одного": 1, "одному": 1, "двух": 2, "двум": 2, "трех": 3, "трем": 3, "четырех": 4, "четырем": 4, "пяти": 5, "шести": 6, "семи": 7, "восьми": 8, "девяти": 9, "десяти": 10, "одиннадцати": 11, "двенадцати": 12][word]
    }

    static func ruMinutes(_ words: String) -> Int {
        let values = ["десять": 10, "одиннадцать": 11, "двенадцать": 12, "тринадцать": 13, "четырнадцать": 14, "пятнадцать": 15, "шестнадцать": 16, "семнадцать": 17, "восемнадцать": 18, "девятнадцать": 19, "двадцать": 20, "тридцать": 30, "сорок": 40, "пятьдесят": 50, "одна": 1, "одну": 1, "две": 2, "три": 3, "четыре": 4, "пять": 5, "шесть": 6, "семь": 7, "восемь": 8, "девять": 9]
        return words.split(separator: " ").reduce(0) { $0 + (values[String($1)] ?? 0) }
    }

    private func russianClock(_ hour: Int?, minute: String?, _ modifier: String?, _ s: inout State) -> Bool {
        guard let hour, let time = PhraseParser.clock(hour, minute: minute.flatMap(Int.init) ?? 0, before: false) else { return false }
        s.time = LocalTime(hour: adjust(time.hour, modifier), minute: time.minute)
        s.meridiem = modifier != nil
        return true
    }

    private func adjust(_ hour: Int, _ modifier: String?) -> Int {
        switch modifier?.trimmingCharacters(in: .whitespaces) {
        case "вечера", "дня":
            return hour < 12 ? hour + 12 : hour
        case "ночи":
            // «В 11 ночи» is late in the evening, «в 2 ночи» the small hours.
            if hour == 12 { return 0 }
            return (6...11).contains(hour) ? hour + 12 : hour
        case "утра":
            return hour == 12 ? 0 : hour
        default:
            return hour
        }
    }

    private func alerts(_ text: String, _ state: inout State) {
        take("за (полчаса)", text, &state) { _, s in s.preAlerts.append(30); return true }
        take("за (?:(\\d{1,4}|пару|два|две|три) )?(минуту|минуты|минут|час|часа|часов|день|дня|дней|неделю|недели|недель)", text, &state) { m, s in
            let unit = group(m, 2, text) ?? ""
            let count = group(m, 1, text).flatMap(number) ?? 1
            if unit.hasPrefix("минут") {
                s.preAlerts.append(count)
            } else if unit.hasPrefix("час") {
                s.preAlerts.append(count * 60)
            } else if unit.hasPrefix("д") {
                s.preAlerts.append(count * 1_440)
            } else {
                s.preAlerts.append(count * 10_080)
            }
            return true
        }
        take("заранее", text, &state) { _, _ in true }
    }

    private func flags(_ text: String, _ state: inout State) {
        take("(очень срочно|очень важно|срочно|важно|обязательно|непременно|в обязательном порядке)", text, &state) { _, s in s.urgent = true; return true }
        take("(?:(?:мне )?(?:надо|нужно) )?не (?:забыть|забудь|забудьте|забывай)(?: бы)?", text, &state) { _, _ in true }
        take("(настойчиво|пока не (сделаю|отмечу))", text, &state) { _, s in s.nag = true; return true }
    }

    private func placeRules(_ text: String, _ state: inout State) {
        guard !places.isEmpty else { return }
        let triggers = "(когда|как) (приду|буду|вернусь|уйду|выйду|уеду)( (в|во|на|с|со|из|от|к))?"
        take("\(triggers) ([\\p{L}-]+)( (и|или) ([\\p{L}-]+))?", text, &state) { m, s in
            let verb = group(m, 2, text) ?? ""
            let words = [group(m, 5, text), group(m, 8, text)].compactMap { $0 }
            let found = words.compactMap(matchPlace)
            guard !found.isEmpty else { return false }
            // «На работу» is where one goes and «с работы» where one leaves, whatever the verb.
            switch group(m, 4, text) {
            case "с", "со", "из", "от": s.placeTrigger = .leave
            case "в", "во", "на", "к": s.placeTrigger = .arrive
            default: s.placeTrigger = ["уйду", "выйду", "уеду"].contains(verb) ? .leave : .arrive
            }
            s.placeNames = found
            return true
        }
    }

    private func matchPlace(_ word: String) -> String? {
        let candidate = stem(word)
        guard candidate.count >= 3 else { return nil }
        return places.first { stem($0.lowercased()) == candidate || (word == "домой" && $0.lowercased() == "дом") }
    }

    private func stem(_ word: String) -> String {
        let lower = word.lowercased()
        for ending in ["ами", "ями", "ой", "ей", "ом", "ем", "ах", "ях", "у", "ю", "а", "я", "е", "ы", "и"] where lower.hasSuffix(ending) && lower.count - ending.count >= 3 {
            return String(lower.dropLast(ending.count))
        }
        return lower
    }

    func nextDate(month: Int, day: Int, year: Int?) -> LocalDate {
        let today = LocalDate(now, in: calendar)
        if let year {
            return LocalDate(year: year, month: month, day: min(day, LocalDate.days(in: month, year: year)))
        }
        var candidate = LocalDate(year: today.year, month: month, day: min(day, LocalDate.days(in: month, year: today.year)))
        if candidate < today {
            candidate = LocalDate(year: today.year + 1, month: month, day: min(day, LocalDate.days(in: month, year: today.year + 1)))
        }
        return candidate
    }

    func resolve(_ state: inout State) -> Schedule? {
        let today = LocalDate(now, in: calendar)
        // A holiday is the day only when nothing else names one; otherwise it stays in the title, «завтра купить подарки на Новый год».
        if let holiday = state.holiday {
            if state.date == nil, state.dayOffset == nil, state.weekdays.isEmpty, state.exact == nil {
                state.date = holiday
            } else if let range = state.holidayRange {
                state.used.removeAll { $0 == range }
            }
        }
        if let exact = state.exact {
            let parts = calendar.dateComponents([.hour, .minute], from: exact)
            return Schedule(start: LocalDate(exact, in: calendar), time: LocalTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0), rule: state.rule)
        }
        if let event = state.sun, state.time == nil {
            var day = state.date ?? today.adding(days: state.dayOffset ?? 0)
            while !state.weekdays.isEmpty, state.date == nil, !state.weekdays.contains(day.weekday) {
                day = day.adding(days: 1)
            }
            state.time = Sun.time(event, on: day, at: coordinate ?? Sun.guess(for: calendar), calendar: calendar) ?? (event == .sunrise ? morning : evening)
            state.meridiem = true
        }
        let hasDate = state.date != nil || state.dayOffset != nil || !state.weekdays.isEmpty
        var time = state.time ?? state.dayPart
        // «Ночью в 2», «днём в 11», «tonight at 12»: of h and h+12 the one closer to the part of the day counts.
        if let explicit = state.time, let part = state.dayPart, !state.meridiem, explicit.hour <= 12 {
            let target = part.hour * 60 + part.minute
            func distance(_ hour: Int) -> Int {
                let gap = abs(hour * 60 + explicit.minute - target)
                return min(gap, 1440 - gap)
            }
            let base = explicit.hour % 12
            let best = [base, base + 12].min { distance($0) < distance($1) } ?? explicit.hour
            time = LocalTime(hour: best, minute: explicit.minute)
        }
        let isToday = state.date == nil && state.dayOffset == 0 && state.weekdays.isEmpty
        // «Сегодня в 3» still means the three that is ahead today, there is just no other day to offer.
        if isToday, let explicit = state.time, state.dayPart == nil, !state.meridiem, state.rule == nil, (1...11).contains(explicit.hour) {
            let early = calendar.date(from: DateComponents(year: today.year, month: today.month, day: today.day, hour: explicit.hour, minute: explicit.minute)) ?? now
            if early <= now {
                time = LocalTime(hour: explicit.hour + 12, minute: explicit.minute)
            }
        }
        // A bare «в 7» means the nearest seven to come; the other reading is offered beside it.
        if let explicit = state.time, state.dayPart == nil, !state.meridiem, !hasDate, !dayNamedBefore, state.rule == nil, (1...11).contains(explicit.hour) {
            let later = LocalTime(hour: explicit.hour + 12, minute: explicit.minute)
            func at(_ clock: LocalTime, _ day: LocalDate) -> Date {
                calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: clock.hour, minute: clock.minute)) ?? now
            }
            if at(explicit, today) > now {
                state.alternative = Schedule(start: today, time: later)
            } else if at(later, today) > now {
                time = later
                state.alternative = Schedule(start: today.adding(days: 1), time: explicit)
            } else {
                state.alternative = Schedule(start: today.adding(days: 1), time: later)
            }
        }
        // «Завтра в 3 забрать детей» is the afternoon, the night is offered beside it.
        var night: LocalTime?
        if let explicit = state.time, time == explicit, state.dayPart == nil, !state.meridiem, (hasDate && !isToday) || dayNamedBefore, state.rule == nil, (1...5).contains(explicit.hour) {
            time = LocalTime(hour: explicit.hour + 12, minute: explicit.minute)
            night = explicit
        }
        guard hasDate || time != nil || state.rule != nil else {
            return nil
        }
        var clock = time ?? morning

        func moment(_ date: LocalDate) -> Date {
            calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: clock.hour, minute: clock.minute)) ?? now
        }

        var start: LocalDate
        if let date = state.date {
            start = date
        } else if let offset = state.dayOffset {
            start = today.adding(days: offset)
            // «В пятницу через неделю» is the first Friday after the week has passed.
            while !state.weekdays.isEmpty, !state.weekdays.contains(start.weekday) {
                start = start.adding(days: 1)
            }
        } else if !state.weekdays.isEmpty {
            start = today
            for step in 0..<8 {
                let candidate = today.adding(days: step)
                if state.weekdays.contains(candidate.weekday), moment(candidate) > now {
                    start = candidate
                    break
                }
            }
            // «В следующую пятницу» early in the week may mean either Friday, the one of the next week goes first.
            if state.nextWeek, state.rule == nil, state.weekdays.count == 1 {
                let first = (calendar.firstWeekday + 5) % 7 + 1
                let weekStart = today.adding(days: -((today.weekday.rawValue - first + 7) % 7))
                if start < weekStart.adding(days: 7) {
                    state.alternative = Schedule(start: start, time: clock)
                    start = start.adding(days: 7)
                }
            }
        } else {
            start = moment(today) > now ? today : today.adding(days: 1)
        }
        if let night, state.alternative == nil {
            state.alternative = Schedule(start: start, time: night)
        }
        // «Сегодня купить хлеб» after the morning: the evening, or an hour from now late in the day.
        if time == nil, state.rule == nil, start == today, moment(today) <= now {
            let evenings = calendar.date(from: DateComponents(year: today.year, month: today.month, day: today.day, hour: evening.hour, minute: evening.minute)) ?? now
            if evenings > now {
                clock = evening
            } else {
                let soon = now.addingTimeInterval(3600)
                let parts = calendar.dateComponents([.hour, .minute], from: soon)
                let minute = min(((parts.minute ?? 0) + 4) / 5 * 5, 55)
                clock = LocalTime(hour: parts.hour ?? 0, minute: minute)
                start = LocalDate(soon, in: calendar)
            }
        }

        var rule = state.rule
        switch rule {
        case .weekly(let days) where days.isEmpty:
            rule = .weekly([start.weekday])
        case .monthlyOnDay(let day) where day == 0:
            rule = .monthlyOnDay(start.day)
        case .monthlyOnDay(let day):
            var candidate = LocalDate(year: today.year, month: today.month, day: min(day, LocalDate.days(in: today.month, year: today.year)))
            if moment(candidate) <= now {
                let next = today.month == 12 ? (today.year + 1, 1) : (today.year, today.month + 1)
                candidate = LocalDate(year: next.0, month: next.1, day: min(day, LocalDate.days(in: next.1, year: next.0)))
            }
            start = candidate
        case .yearly(let month, let day) where month == 0 || day == 0:
            rule = .yearly(month: start.month, day: start.day)
        default:
            break
        }
        if rule != nil, state.date == nil, state.dayOffset == nil, moment(start) <= now {
            if case .monthlyOnDay = rule {} else {
                start = start.adding(days: 1)
            }
        }
        // «Сегодня в полночь», «heute Nacht um 2»: the small hours of a named night belong to the next date.
        if state.date != nil || state.dayOffset != nil || !state.weekdays.isEmpty, rule == nil {
            let night = state.dayPart.map { $0.hour >= 21 } ?? false
            if (clock.hour == 0 && clock.minute == 0 && state.dayOffset == 0) || (night && clock.hour < 6) {
                start = start.adding(days: 1)
            }
        }
        // «До пятницы»: a deadline also rings the evening before.
        if state.deadline, rule == nil, let moment = calendar.date(from: DateComponents(year: start.year, month: start.month, day: start.day, hour: clock.hour, minute: clock.minute)) {
            let eve = start.adding(days: -1)
            if let before = calendar.date(from: DateComponents(year: eve.year, month: eve.month, day: eve.day, hour: evening.hour, minute: evening.minute)), before > now, moment > before {
                state.preAlerts.append(Int(moment.timeIntervalSince(before) / 60))
            }
        }
        var end = rule == nil ? RepeatEnd.never : state.end
        if let span = state.span, rule != nil, end == .never {
            end = .until(start.adding(days: max(span, 1) - 1))
        }
        return Schedule(start: start, time: clock, rule: rule, end: end)
    }

    func title(_ input: String, used: [Range<Int>], fillers: Set<String>, dangling: Set<String>, lead: Set<String> = []) -> String {
        var characters = Array(input)
        for range in used {
            for index in range where index < characters.count {
                characters[index] = " "
            }
        }
        // A preposition right before a recognised time belonged to it; one that opens the rest, as in «к врачу», is the title's own.
        for range in used {
            var end = min(range.lowerBound, characters.count)
            while true {
                var cursor = end
                while cursor > 0, characters[cursor - 1].isWhitespace {
                    cursor -= 1
                }
                var start = cursor
                while start > 0, !characters[start - 1].isWhitespace {
                    start -= 1
                }
                guard start < cursor, dangling.contains(String(characters[start..<cursor]).lowercased().trimmingCharacters(in: .punctuationCharacters)) else { break }
                for index in start..<cursor {
                    characters[index] = " "
                }
                end = start
            }
        }
        let words = String(characters)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !fillers.contains($0.lowercased().trimmingCharacters(in: .punctuationCharacters)) }
        var trimmed = words
        while let first = trimmed.first?.lowercased(), lead.contains(first.trimmingCharacters(in: .punctuationCharacters)) || (dangling.contains(first) && PhraseParser.conjunctions.contains(first)) {
            trimmed.removeFirst()
        }
        while let last = trimmed.last, dangling.contains(last.lowercased()) {
            trimmed.removeLast()
        }
        var result = trimmed.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-–—"))
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        guard let first = result.first else { return "" }
        return String(first).uppercased() + result.dropFirst()
    }

    func merge(_ ranges: [Range<Int>]) -> [Range<Int>] {
        ranges.sorted { $0.lowerBound < $1.lowerBound }
    }
}
