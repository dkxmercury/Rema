import Foundation

extension PhraseParser {
    static let ukMonths = "(січня|лютого|березня|квітня|травня|червня|липня|серпня|вересня|жовтня|листопада|грудня)"
    static let ukWeekdays = "(понеділ\\w*|пн|вівтор\\w*|(?<!\\d )вт|серед(?:а|у|и|ою|і)|ср|четвер(?:г\\w*)?|чт|п'ятниц\\w*|пятниц\\w*|пт|субот\\w*|сб|неділ\\w*|нд)"
    private static let ukFillers: Set<String> = ["нагадай", "нагадайте", "нагадати", "мені", "будь", "ласка", "треба", "потрібно"]
    private static let ukDangling: Set<String> = ["і", "й", "та", "а", "в", "у", "на", "з", "із", "до", "о", "об", "по"]

    static func looksUkrainian(_ text: String, preferred: String?) -> Bool {
        let lower = text.lowercased()
        if lower.contains(where: { "іїєґ".contains($0) }) { return true }
        if lower.contains(where: { "ыэъё".contains($0) }) { return false }
        // Russian has no apostrophe inside a word and says «в 7», not «о 7».
        if lower.range(of: "\\p{Cyrillic}['’ʼ]\\p{Cyrillic}|(?:^|\\s)о \\d", options: .regularExpression) != nil { return true }
        return preferred?.hasPrefix("uk") == true
    }

    func parseUkrainian(_ input: String) -> ParsedPhrase {
        let text = input.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "ʼ", with: "'")
        func pass(_ text: String, _ state: inout State) {
            extras(text, &state, PhraseParser.ukrainianExtras, weekday: ukWeekday)
            ukRepeats(text, &state)
            limits(text, &state, PhraseParser.ukrainianLimits, weekday: ukWeekday, month: ukMonth)
            ukOffsets(text, &state)
            ukDates(text, &state)
            ukTimes(text, &state)
            ukAlerts(text, &state)
            ukFlags(text, &state)
            ukPlaces(text, &state)
        }
        var state = corrected(text, PhraseParser.ukrainianCorrection, pass)

        let schedule = resolve(&state)
        return ParsedPhrase(
            title: title(input, used: state.used, fillers: PhraseParser.ukFillers, dangling: PhraseParser.ukDangling),
            schedule: schedule,
            preAlerts: Array(Set(state.preAlerts)).sorted(by: >),
            urgent: state.urgent,
            nag: state.nag,
            placeTrigger: state.placeTrigger,
            placeNames: state.placeNames,
            highlights: merge(state.used),
            hasExplicitTime: state.time != nil || state.exact != nil || state.dayPart != nil,
            alternative: state.alternative,
            hasExplicitDay: state.date != nil || state.dayOffset != nil || !state.weekdays.isEmpty || state.rule != nil || state.exact != nil,
            corrected: state.corrected,
            usedPart: state.time == nil && state.exact == nil ? state.dayPart : nil
        )
    }

    private func ukWeekday(_ word: String) -> Weekday? {
        if word.hasPrefix("пн") || word.hasPrefix("понед") { return .monday }
        if word.hasPrefix("вт") || word.hasPrefix("вівт") { return .tuesday }
        if word.hasPrefix("ср") || word.hasPrefix("серед") { return .wednesday }
        if word.hasPrefix("чт") || word.hasPrefix("четв") { return .thursday }
        if word.hasPrefix("пт") || word.hasPrefix("п'ят") || word.hasPrefix("пят") { return .friday }
        if word.hasPrefix("сб") || word.hasPrefix("субот") { return .saturday }
        if word.hasPrefix("нд") || word.hasPrefix("неділ") { return .sunday }
        return nil
    }

    private func ukMonth(_ word: String) -> Int? {
        let stems = ["січ", "лют", "берез", "квіт", "трав", "черв", "лип", "серп", "верес", "жовт", "листоп", "груд"]
        return stems.firstIndex { word.hasPrefix($0) }.map { $0 + 1 }
    }

    private func ukNumber(_ word: String) -> Int? {
        if let value = Int(word) { return value }
        switch word {
        case "одну", "один", "одна", "хвилину", "годину", "день", "тиждень", "місяць": return 1
        case "пару", "два", "дві": return 2
        case "три": return 3
        case "чотири": return 4
        case "п'ять": return 5
        default: return nil
        }
    }

    private func ukRepeats(_ text: String, _ state: inout State) {
        take("(щодня|щоденно|кожен день|кожного дня)", text, &state) { _, s in s.rule = .daily; return true }
        take("(по буднях|у будні|в будні|щобудня|по робочих днях)", text, &state) { _, s in s.rule = .weekdays; return true }
        take("кожні (\\d{1,4}) (дні|днів)", text, &state) { m, s in
            guard let count = group(m, 1, text).flatMap(Int.init), count > 0 else { return false }
            s.rule = count == 1 ? .daily : .everyDays(count)
            return true
        }
        let list = "\(PhraseParser.ukWeekdays)((\\s*(,|і|й|та)\\s*)\(PhraseParser.ukWeekdays))*"
        take("(кожен|кожного|кожну|кожної|по) \(list)", text, &state) { m, s in
            guard let whole = Range(m.range, in: text) else { return false }
            let words: [String] = String(text[whole]).split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
            let days = words.compactMap(self.ukWeekday)
            guard !days.isEmpty else { return false }
            s.weekdays = Array(Set(days)).sorted()
            s.rule = .weekly(s.weekdays)
            return true
        }
        take("(щопонеділка|щовівторка|щосереди|щочетверга|щоп'ятниці|щосуботи|щонеділі)", text, &state) { m, s in
            guard let word = group(m, 1, text), let day = self.ukWeekday(String(word.dropFirst(2))) else { return false }
            s.weekdays = [day]
            s.rule = .weekly([day])
            return true
        }
        take("(щотижня|кожного тижня)", text, &state) { _, s in s.rule = .weekly([]); return true }
        take("(щомісяця|кожного місяця)( (\\d{1,2})(-?го)?( числа)?)?", text, &state) { m, s in
            s.rule = .monthlyOnDay(group(m, 3, text).flatMap(Int.init) ?? 0)
            return true
        }
        take("(щороку|кожного року|щорічно)( (\\d{1,2}) \(PhraseParser.ukMonths))?", text, &state) { m, s in
            if let day = group(m, 3, text).flatMap(Int.init), let month = group(m, 4, text).flatMap(self.ukMonth) {
                s.rule = .yearly(month: month, day: day)
                s.date = nextDate(month: month, day: day, year: nil)
            } else {
                s.rule = .yearly(month: 0, day: 0)
            }
            return true
        }
    }

    private func ukOffsets(_ text: String, _ state: inout State) {
        take("через (півгодини|півтори години)", text, &state) { m, s in
            let minutes = group(m, 1, text) == "півгодини" ? 30 : 90
            s.exact = now.addingTimeInterval(Double(minutes) * 60)
            return true
        }
        take("через (?:(\\d{1,4}|одну|один|пару|два|дві|три|чотири|п'ять) )?(хвилину|хвилини|хвилин|годину|години|годин|день|дні|днів|тиждень|тижні|тижнів|місяць|місяці|місяців)", text, &state) { m, s in
            let unit = group(m, 2, text) ?? ""
            let count = group(m, 1, text).flatMap(ukNumber) ?? 1
            if unit.hasPrefix("хвилин") {
                s.exact = now.addingTimeInterval(Double(count) * 60)
            } else if unit.hasPrefix("годин") {
                s.exact = now.addingTimeInterval(Double(count) * 3600)
            } else if unit.hasPrefix("д") {
                s.dayOffset = count
            } else if unit.hasPrefix("тиж") {
                s.dayOffset = count * 7
            } else if let date = calendar.date(byAdding: .month, value: count, to: now) {
                s.date = LocalDate(date, in: calendar)
            }
            return true
        }
    }

    private func ukDates(_ text: String, _ state: inout State) {
        take("(сьогодні)", text, &state) { _, s in s.dayOffset = 0; return true }
        take("(післязавтра)", text, &state) { _, s in s.dayOffset = 2; return true }
        take("(завтра)", text, &state) { _, s in s.dayOffset = 1; return true }
        take("(\\d{1,2}) \(PhraseParser.ukMonths)( (\\d{4}))?", text, &state) { m, s in
            guard let day = group(m, 1, text).flatMap(Int.init), let month = group(m, 2, text).flatMap(self.ukMonth), (1...31).contains(day) else { return false }
            s.date = nextDate(month: month, day: day, year: group(m, 4, text).flatMap(Int.init))
            if case .yearly = s.rule {
                s.rule = .yearly(month: month, day: day)
            }
            return true
        }
        take("(?<!(?:о|об|на|до|з|після|близько) )(\\d{1,2})\\.(\\d{1,2})(?:\\.(\\d{4}))?(?![.:]?\\d)", text, &state) { m, s in
            guard let day = group(m, 1, text).flatMap(Int.init), let month = group(m, 2, text).flatMap(Int.init), (1...12).contains(month), (1...LocalDate.days(in: month, year: 2028)).contains(day) else { return false }
            s.date = nextDate(month: month, day: day, year: group(m, 3, text).flatMap(Int.init))
            return true
        }
        take("(?:в |у |во )?(наступн\\w+ )?\(PhraseParser.ukWeekdays)", text, &state) { m, s in
            guard s.rule == nil || s.rule == .weekly([]), let word = group(m, 2, text), let day = self.ukWeekday(word) else { return false }
            s.weekdays = [day]
            s.nextWeek = saysNext(m, text)
            if s.rule == .weekly([]) {
                s.rule = .weekly([day])
            }
            return true
        }
    }

    private func ukTimes(_ text: String, _ state: inout State) {
        let modifier = "( ранку| вечора| дня| ночі)?"
        let accusative = "(першу|другу|третю|четверту|п'яту|шосту|сьому|восьму|дев'яту|десяту|одинадцяту|дванадцяту)"
        let nominative = "(перша|друга|третя|четверта|п'ята|шоста|сьома|восьма|дев'ята|десята|одинадцята|дванадцята)"
        let locative = "(двадцять першій|двадцять другій|двадцять третій|двадцятій|першій|другій|третій|четвертій|п'ятій|шостій|сьомій|восьмій|дев'ятій|десятій|одинадцятій|дванадцятій|тринадцятій|чотирнадцятій|п'ятнадцятій|шістнадцятій|сімнадцятій|вісімнадцятій|дев'ятнадцятій)"
        let cardinal = "(одна|одну|дві|три|чотири|п'ять|шість|сім|вісім|дев'ять|десять|одинадцять|дванадцять)"
        let genitive = "(двадцять першої|двадцять другої|двадцять третьої|двадцятої|першої|другої|третьої|четвертої|п'ятої|шостої|сьомої|восьмої|дев'ятої|десятої|одинадцятої|дванадцятої|тринадцятої|чотирнадцятої|п'ятнадцятої|шістнадцятої|сімнадцятої|вісімнадцятої|дев'ятнадцятої)"
        take("(?:близько|ближче до|десь до) (?:(\\d{1,2})(?:[:.](\\d{2}))?|\(genitive))(?: години)?\(modifier)(?! \(PhraseParser.ukMonths))", text, &state) { m, s in
            ukClock(group(m, 1, text).flatMap(Int.init) ?? group(m, 3, text).flatMap(PhraseParser.ukOrdinal), minute: group(m, 2, text).flatMap(Int.init) ?? 0, before: false, group(m, 4, text), &s)
        }
        take("(?:приблизно|десь|орієнтовно) (?:о|об) (?:(\\d{1,2})(?:[:.](\\d{2}))?|\(locative))(?: годині)?\(modifier)(?! \(PhraseParser.ukMonths))", text, &state) { m, s in
            ukClock(group(m, 1, text).flatMap(Int.init) ?? group(m, 3, text).flatMap(PhraseParser.ukOrdinal), minute: group(m, 2, text).flatMap(Int.init) ?? 0, before: false, group(m, 4, text), &s)
        }
        take("(?:між|з) (\\d{1,2})(?:[:.](\\d{2}))? (?:і|й|та|до) \\d{1,2}(?:[:.]\\d{2})?(?: години)?\(modifier)(?! \(PhraseParser.ukMonths))", text, &state) { m, s in
            ukClock(group(m, 1, text).flatMap(Int.init), minute: group(m, 2, text).flatMap(Int.init) ?? 0, before: false, group(m, 3, text), &s)
        }
        take("(?:о пів|опів|пів) на \(accusative)\(modifier)", text, &state) { m, s in
            ukClock(group(m, 1, text).flatMap(PhraseParser.ukOrdinal), minute: 30, before: true, group(m, 2, text), &s)
        }
        // «Чверть на третю» is a quarter past two, that is 45 minutes before three.
        take("(?:о |об )?чверть на \(accusative)\(modifier)", text, &state) { m, s in
            ukClock(group(m, 1, text).flatMap(PhraseParser.ukOrdinal), minute: 45, before: true, group(m, 2, text), &s)
        }
        take("(?:о |об )?за (двадцять п'ять|двадцять|п'ятнадцять|десять|п'ять|чверть|\\d{1,2})(?: хвилин[аи]?)? \(nominative)\(modifier)", text, &state) { m, s in
            let count = group(m, 1, text) ?? ""
            return ukClock(group(m, 2, text).flatMap(PhraseParser.ukOrdinal), minute: Int(count) ?? PhraseParser.ukMinutes[count] ?? 0, before: true, group(m, 3, text), &s)
        }
        take("без (двадцяти п'яти|двадцяти|п'ятнадцяти|десяти|п'яти|чверті|\\d{1,2})(?: хвилин)? \(cardinal)\(modifier)", text, &state) { m, s in
            let count = group(m, 1, text) ?? ""
            return ukClock(group(m, 2, text).flatMap { PhraseParser.ukCardinals[$0] }, minute: Int(count) ?? PhraseParser.ukMinutes[count] ?? 0, before: true, group(m, 3, text), &s)
        }
        let minuteWords = "(десять|одинадцять|дванадцять|тринадцять|чотирнадцять|п'ятнадцять|шістнадцять|сімнадцять|вісімнадцять|дев'ятнадцять|(?:двадцять|тридцять|сорок|п'ятдесят)(?: (?:одна|одну|дві|три|чотири|п'ять|шість|сім|вісім|дев'ять))?)"
        take("(?:о|об) \(locative)(?: \(minuteWords))?(?: годині)?\(modifier)", text, &state) { m, s in
            ukClock(group(m, 1, text).flatMap(PhraseParser.ukOrdinal), minute: group(m, 2, text).map(PhraseParser.ukMinuteWords) ?? 0, before: false, group(m, 3, text), &s)
        }
        take("(?:о |об |на |до )?(\\d{1,2})[:.](\\d{2})\(modifier)", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), let minute = group(m, 2, text).flatMap(Int.init), hour < 24, minute < 60 else { return false }
            s.time = LocalTime(hour: ukHour(hour, group(m, 3, text)), minute: minute)
            s.meridiem = group(m, 3, text) != nil || PhraseParser.twentyFour(group(m, 1, text))
            return true
        }
        // «На 4 особи» is an amount, not a time.
        take("(?:о|об) (\\d{1,2})(?: годин\\w*)?\(modifier)(?! \(PhraseParser.ukMonths))(?! (?:(?:кг|км|грн|шт|раз|рази|разів|люди|людей|рік|роки|років|місця|місць|місце|особи|осіб|особу|особа)(?![\\p{L}])|(?:чолов|відсот|гривен|хвилин|днів|тижн|місяц|друз|гост)\\w*))", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), hour < 24 else { return false }
            s.time = LocalTime(hour: ukHour(hour, group(m, 2, text)), minute: 0)
            s.meridiem = group(m, 2, text) != nil
            return true
        }
        take("(?:опівдні|о полудні)", text, &state) { _, s in s.time = LocalTime(hour: 12, minute: 0); return true }
        take("(?:опівночі)", text, &state) { _, s in s.time = LocalTime(hour: 0, minute: 0); return true }
        take("(вранці|зранку|ранком)", text, &state) { _, s in s.dayPart = morning; return true }
        take("(вдень|удень)", text, &state) { _, s in s.dayPart = LocalTime(hour: 13, minute: 0); return true }
        take("(ввечері|увечері|ввечорі)", text, &state) { _, s in s.dayPart = evening; return true }
        take("(вночі|уночі)", text, &state) { _, s in s.dayPart = LocalTime(hour: 23, minute: 0); return true }
    }

    private static let ukCardinals = ["одна": 1, "одну": 1, "дві": 2, "три": 3, "чотири": 4, "п'ять": 5, "шість": 6, "сім": 7, "вісім": 8, "дев'ять": 9, "десять": 10, "одинадцять": 11, "дванадцять": 12]
    private static let ukMinutes = ["п'ять": 5, "п'яти": 5, "десять": 10, "десяти": 10, "п'ятнадцять": 15, "п'ятнадцяти": 15, "чверть": 15, "чверті": 15, "двадцять": 20, "двадцяти": 20, "двадцять п'ять": 25, "двадцяти п'яти": 25, "тридцять": 30, "сорок": 40, "сорок п'ять": 45, "п'ятдесят": 50]

    static func ukMinuteWords(_ words: String) -> Int {
        let values = ["десять": 10, "одинадцять": 11, "дванадцять": 12, "тринадцять": 13, "чотирнадцять": 14, "п'ятнадцять": 15, "шістнадцять": 16, "сімнадцять": 17, "вісімнадцять": 18, "дев'ятнадцять": 19, "двадцять": 20, "тридцять": 30, "сорок": 40, "п'ятдесят": 50, "одна": 1, "одну": 1, "дві": 2, "три": 3, "чотири": 4, "п'ять": 5, "шість": 6, "сім": 7, "вісім": 8, "дев'ять": 9]
        return words.split(separator: " ").reduce(0) { $0 + (values[String($1)] ?? 0) }
    }

    static func ukOrdinal(_ word: String) -> Int? {
        let stem = word.hasSuffix("ьої") ? String(word.dropLast(3)) : word.hasSuffix("ої") || word.hasSuffix("ій") ? String(word.dropLast(2)) : String(word.dropLast())
        return ["перш": 1, "друг": 2, "трет": 3, "четверт": 4, "п'ят": 5, "шост": 6, "сьом": 7, "восьм": 8, "дев'ят": 9, "десят": 10, "одинадцят": 11, "дванадцят": 12, "тринадцят": 13, "чотирнадцят": 14, "п'ятнадцят": 15, "шістнадцят": 16, "сімнадцят": 17, "вісімнадцят": 18, "дев'ятнадцят": 19, "двадцят": 20, "двадцять перш": 21, "двадцять друг": 22, "двадцять трет": 23][stem]
    }

    private func ukClock(_ hour: Int?, minute: Int, before: Bool, _ modifier: String?, _ s: inout State) -> Bool {
        guard let hour, let time = PhraseParser.clock(hour, minute: minute, before: before) else { return false }
        s.time = LocalTime(hour: ukHour(time.hour, modifier), minute: time.minute)
        s.meridiem = modifier != nil
        return true
    }

    private func ukHour(_ hour: Int, _ modifier: String?) -> Int {
        switch modifier?.trimmingCharacters(in: .whitespaces) {
        case "вечора", "дня":
            return hour < 12 ? hour + 12 : hour
        case "ночі":
            if hour == 12 { return 0 }
            return (6...11).contains(hour) ? hour + 12 : hour
        case "ранку":
            return hour == 12 ? 0 : hour
        default:
            return hour
        }
    }

    private func ukAlerts(_ text: String, _ state: inout State) {
        take("за (півгодини)", text, &state) { _, s in s.preAlerts.append(30); return true }
        take("за (?:(\\d{1,4}|пару|два|дві|три) )?(хвилину|хвилини|хвилин|годину|години|годин|день|дні|днів|тиждень|тижні|тижнів)", text, &state) { m, s in
            let unit = group(m, 2, text) ?? ""
            let count = group(m, 1, text).flatMap(ukNumber) ?? 1
            if unit.hasPrefix("хвилин") {
                s.preAlerts.append(count)
            } else if unit.hasPrefix("годин") {
                s.preAlerts.append(count * 60)
            } else if unit.hasPrefix("д") {
                s.preAlerts.append(count * 1_440)
            } else {
                s.preAlerts.append(count * 10_080)
            }
            return true
        }
        take("заздалегідь", text, &state) { _, _ in true }
    }

    private func ukFlags(_ text: String, _ state: inout State) {
        take("(дуже терміново|дуже важливо|терміново|важливо|обов'язково|неодмінно)", text, &state) { _, s in s.urgent = true; return true }
        take("(?:(?:мені )?(?:треба|потрібно) )?не (?:забути|забудь|забудьте|забувай)", text, &state) { _, _ in true }
        take("(наполегливо|поки не (зроблю|позначу))", text, &state) { _, s in s.nag = true; return true }
    }

    private func ukPlaces(_ text: String, _ state: inout State) {
        guard !places.isEmpty else { return }
        let triggers = "(коли|як) (прийду|буду|повернуся|приїду|піду|вийду|поїду)( (в|у|на|з|із|зі|від|до))?"
        take("\(triggers) ([\\p{L}'-]+)( (і|або|чи) ([\\p{L}'-]+))?", text, &state) { m, s in
            let verb = group(m, 2, text) ?? ""
            let words = [group(m, 5, text), group(m, 8, text)].compactMap { $0 }
            let found = words.compactMap(ukPlace)
            guard !found.isEmpty else { return false }
            switch group(m, 4, text) {
            case "з", "із", "зі", "від": s.placeTrigger = .leave
            case "в", "у", "на", "до": s.placeTrigger = .arrive
            default: s.placeTrigger = ["піду", "вийду", "поїду"].contains(verb) ? .leave : .arrive
            }
            s.placeNames = found
            return true
        }
    }

    private func ukPlace(_ word: String) -> String? {
        let candidate = ukStem(word)
        guard candidate.count >= 3 else { return nil }
        return places.first { place in
            let name = place.lowercased()
            return ukStem(name) == candidate || (word == "додому" && (name == "дім" || name == "дом"))
        }
    }

    private func ukStem(_ word: String) -> String {
        let lower = word.lowercased()
        for ending in ["ами", "ями", "ою", "ею", "ом", "ем", "ах", "ях", "у", "ю", "а", "я", "і", "и", "е"] where lower.hasSuffix(ending) && lower.count - ending.count >= 3 {
            return String(lower.dropLast(ending.count))
        }
        return lower
    }
}
