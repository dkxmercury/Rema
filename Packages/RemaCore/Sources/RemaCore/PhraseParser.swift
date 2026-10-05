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
}

public struct PhraseParser {
    public let now: Date
    public let calendar: Calendar
    public let morning: LocalTime
    public let evening: LocalTime
    public let places: [String]

    public init(now: Date, calendar: Calendar, morning: LocalTime, evening: LocalTime, places: [String] = []) {
        self.now = now
        self.calendar = calendar
        self.morning = morning
        self.evening = evening
        self.places = places
    }

    private static let months = ["январ", "феврал", "март", "апрел", "ма", "июн", "июл", "август", "сентябр", "октябр", "ноябр", "декабр"]
    private static let monthPattern = "(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря)"
    private static let weekdayPattern = "(понедельник\\w*|пн|вторник\\w*|вт|сред\\w*|ср|четверг\\w*|чт|пятниц\\w*|пт|суббот\\w*|сб|воскресень\\w*|вс)"
    private static let fillers: Set<String> = ["напомни", "напомните", "напомнить", "мне", "пожалуйста", "надо", "нужно"]
    private static let dangling: Set<String> = ["и", "а", "в", "во", "на", "с", "со", "к", "по"]

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
    }

    public func parse(_ input: String) -> ParsedPhrase {
        if !input.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }), input.contains(where: \.isLetter) {
            return parseEnglish(input)
        }
        let text = input.lowercased().replacingOccurrences(of: "ё", with: "е")
        var state = State()

        repeats(text, &state)
        offsets(text, &state)
        dates(text, &state)
        times(text, &state)
        alerts(text, &state)
        flags(text, &state)
        placeRules(text, &state)

        let schedule = resolve(&state)
        return ParsedPhrase(
            title: title(input, used: state.used, fillers: PhraseParser.fillers, dangling: PhraseParser.dangling),
            schedule: schedule,
            preAlerts: Array(Set(state.preAlerts)).sorted(by: >),
            urgent: state.urgent,
            nag: state.nag,
            placeTrigger: state.placeTrigger,
            placeNames: state.placeNames,
            highlights: merge(state.used),
            hasExplicitTime: state.time != nil || state.exact != nil || state.dayPart != nil
        )
    }

    func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\d])" + pattern + "(?![\\p{L}\\d])", options: [.caseInsensitive]) else { return [] }
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

    func isFree(_ range: Range<Int>, _ state: State) -> Bool {
        !state.used.contains { $0.overlaps(range) }
    }

    func take(_ pattern: String, _ text: String, _ state: inout State, _ apply: (NSTextCheckingResult, inout State) -> Bool) {
        for match in matches(pattern, in: text) {
            guard let range = span(match, text), isFree(range, state) else { continue }
            if apply(match, &state) {
                state.used.append(range)
            }
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
        case "три": return 3
        case "четыре": return 4
        case "пять": return 5
        default: return nil
        }
    }

    private func repeats(_ text: String, _ state: inout State) {
        take("(каждый день|ежедневно)", text, &state) { _, s in s.rule = .daily; return true }
        take("(по будням|каждый будний день|по рабочим дням)", text, &state) { _, s in s.rule = .weekdays; return true }
        take("каждые (\\d+) (дня|дней)", text, &state) { m, s in
            guard let count = group(m, 1, text).flatMap(Int.init), count > 0 else { return false }
            s.rule = count == 1 ? .daily : .everyDays(count)
            return true
        }
        let list = "\(PhraseParser.weekdayPattern)((\\s*(,|и)\\s*)\(PhraseParser.weekdayPattern))*"
        take("(каждый|каждую|каждое|по) \(list)", text, &state) { m, s in
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
        take("через (?:(\\d+|одну|один|пару|два|две|три|четыре|пять) )?(минуту|минуты|минут|час|часа|часов|день|дня|дней|неделю|недели|недель|месяц|месяца|месяцев)", text, &state) { m, s in
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
        take("(сегодня)", text, &state) { _, s in s.dayOffset = 0; return true }
        take("(послезавтра)", text, &state) { _, s in s.dayOffset = 2; return true }
        take("(завтра)", text, &state) { _, s in s.dayOffset = 1; return true }
        take("(\\d{1,2}) \(PhraseParser.monthPattern)( (\\d{4}))?", text, &state) { m, s in
            guard let day = group(m, 1, text).flatMap(Int.init), let month = group(m, 2, text).flatMap(self.month), (1...31).contains(day) else { return false }
            let year = group(m, 4, text).flatMap(Int.init)
            s.date = nextDate(month: month, day: day, year: year)
            if case .yearly = s.rule {
                s.rule = .yearly(month: month, day: day)
            }
            return true
        }
        take("(?:в |во )?(следующ\\w+ )?\(PhraseParser.weekdayPattern)", text, &state) { m, s in
            guard s.rule == nil, let word = group(m, 2, text), let day = self.weekday(word) else { return false }
            s.weekdays = [day]
            return true
        }
    }

    private func times(_ text: String, _ state: inout State) {
        let modifier = "( утра| вечера| дня| ночи)?"
        take("(?:в |к )?(\\d{1,2})[:.](\\d{2})\(modifier)", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), let minute = group(m, 2, text).flatMap(Int.init), hour < 24, minute < 60 else { return false }
            s.time = LocalTime(hour: adjust(hour, group(m, 3, text)), minute: minute)
            return true
        }
        take("(?:в|к) (\\d{1,2})(?: час\\w*)?\(modifier)(?! \(PhraseParser.monthPattern))", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), hour < 24 else { return false }
            s.time = LocalTime(hour: adjust(hour, group(m, 2, text)), minute: 0)
            return true
        }
        take("в полдень", text, &state) { _, s in s.time = LocalTime(hour: 12, minute: 0); return true }
        take("в полночь", text, &state) { _, s in s.time = LocalTime(hour: 0, minute: 0); return true }
        take("(утром)", text, &state) { _, s in s.dayPart = morning; return true }
        take("(днем)", text, &state) { _, s in s.dayPart = LocalTime(hour: 13, minute: 0); return true }
        take("(вечером)", text, &state) { _, s in s.dayPart = evening; return true }
        take("(ночью)", text, &state) { _, s in s.dayPart = LocalTime(hour: 23, minute: 0); return true }
    }

    private func adjust(_ hour: Int, _ modifier: String?) -> Int {
        switch modifier?.trimmingCharacters(in: .whitespaces) {
        case "вечера", "дня":
            return hour < 12 ? hour + 12 : hour
        case "ночи":
            return hour == 12 ? 0 : hour
        case "утра":
            return hour == 12 ? 0 : hour
        default:
            return hour
        }
    }

    private func alerts(_ text: String, _ state: inout State) {
        take("за (полчаса)", text, &state) { _, s in s.preAlerts.append(30); return true }
        take("за (?:(\\d+|пару|два|две|три) )?(минуту|минуты|минут|час|часа|часов|день|дня|дней|неделю|недели|недель)", text, &state) { m, s in
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
        take("(срочно|важно)", text, &state) { _, s in s.urgent = true; return true }
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
            s.placeTrigger = ["уйду", "выйду", "уеду"].contains(verb) ? .leave : .arrive
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
        if let exact = state.exact {
            let parts = calendar.dateComponents([.hour, .minute], from: exact)
            return Schedule(start: LocalDate(exact, in: calendar), time: LocalTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0), rule: state.rule)
        }
        let hasDate = state.date != nil || state.dayOffset != nil || !state.weekdays.isEmpty
        var time = state.time ?? state.dayPart
        if let explicit = state.time, let part = state.dayPart, part.hour >= 12, explicit.hour < 12 {
            time = LocalTime(hour: explicit.hour + 12, minute: explicit.minute)
        }
        guard hasDate || time != nil || state.rule != nil else {
            return nil
        }
        let clock = time ?? morning

        func moment(_ date: LocalDate) -> Date {
            calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: clock.hour, minute: clock.minute)) ?? now
        }

        var start: LocalDate
        if let date = state.date {
            start = date
        } else if let offset = state.dayOffset {
            start = today.adding(days: offset)
        } else if !state.weekdays.isEmpty {
            start = today
            for step in 0..<8 {
                let candidate = today.adding(days: step)
                if state.weekdays.contains(candidate.weekday), moment(candidate) > now {
                    start = candidate
                    break
                }
            }
        } else {
            start = moment(today) > now ? today : today.adding(days: 1)
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
        return Schedule(start: start, time: clock, rule: rule)
    }

    func title(_ input: String, used: [Range<Int>], fillers: Set<String>, dangling: Set<String>, lead: Set<String> = []) -> String {
        var characters = Array(input)
        for range in used {
            for index in range where index < characters.count {
                characters[index] = " "
            }
        }
        let words = String(characters)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !fillers.contains($0.lowercased().trimmingCharacters(in: .punctuationCharacters)) }
        var trimmed = words
        while let first = trimmed.first, lead.contains(first.lowercased().trimmingCharacters(in: .punctuationCharacters)) || dangling.contains(first.lowercased()) {
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
