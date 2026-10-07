import Foundation

extension PhraseParser {
    private static let englishMonths = "(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)\\.?"
    static let englishWeekdays = "(mondays?|mon|tuesdays?|tues|tue|wednesdays?|wed|thursdays?|thurs|thur|thu|fridays?|fri|saturdays?|sat|sundays?|sun)"
    private static let englishCount = "(\\d+|an|a|one|two|three|four|five|ten|fifteen|twenty|thirty|a couple of|couple of)"
    private static let englishFillers: Set<String> = ["please"]
    private static let englishLead: Set<String> = ["remind", "me", "to", "about", "i", "need", "have", "must", "should", "don't", "dont", "forget", "please"]
    private static let englishDangling: Set<String> = ["at", "on", "in", "to", "and", "the", "by", "for", "of", "from", "every"]

    func parseEnglish(_ input: String) -> ParsedPhrase {
        let text = input.lowercased().replacingOccurrences(of: "’", with: "'")
        var state = State()

        extras(text, &state, PhraseParser.englishExtras, weekday: englishWeekday)
        englishRepeats(text, &state)
        englishOffsets(text, &state)
        englishDates(text, &state)
        englishTimes(text, &state)
        englishAlerts(text, &state)
        englishFlags(text, &state)
        englishPlaces(text, &state)

        let schedule = resolve(&state)
        return ParsedPhrase(
            title: title(input, used: state.used + matches(",? ?remind me( to| about)?", in: text).compactMap { span($0, text) }, fillers: PhraseParser.englishFillers, dangling: PhraseParser.englishDangling, lead: PhraseParser.englishLead),
            schedule: schedule,
            preAlerts: Array(Set(state.preAlerts)).sorted(by: >),
            urgent: state.urgent,
            nag: state.nag,
            placeTrigger: state.placeTrigger,
            placeNames: state.placeNames,
            highlights: merge(state.used),
            hasExplicitTime: state.time != nil || state.exact != nil || state.dayPart != nil,
            alternative: state.alternative
        )
    }

    private func englishWeekday(_ word: String) -> Weekday? {
        if word.hasPrefix("mon") { return .monday }
        if word.hasPrefix("tue") { return .tuesday }
        if word.hasPrefix("wed") { return .wednesday }
        if word.hasPrefix("thu") { return .thursday }
        if word.hasPrefix("fri") { return .friday }
        if word.hasPrefix("sat") { return .saturday }
        if word.hasPrefix("sun") { return .sunday }
        return nil
    }

    private func englishMonth(_ word: String) -> Int? {
        let names = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return names.firstIndex { word.hasPrefix($0) }.map { $0 + 1 }
    }

    private func englishNumber(_ word: String) -> Int? {
        if let value = Int(word) { return value }
        switch word {
        case "a", "an", "one": return 1
        case "two", "a couple of", "couple of": return 2
        case "three": return 3
        case "four": return 4
        case "five": return 5
        case "ten": return 10
        case "fifteen": return 15
        case "twenty": return 20
        case "thirty": return 30
        default: return nil
        }
    }

    private func englishRepeats(_ text: String, _ state: inout State) {
        take("(every day|daily)", text, &state) { _, s in s.rule = .daily; return true }
        take("(on weekdays|every weekday|weekdays)", text, &state) { _, s in s.rule = .weekdays; return true }
        take("every (\\d+) days", text, &state) { m, s in
            guard let count = group(m, 1, text).flatMap(Int.init), count > 0 else { return false }
            s.rule = count == 1 ? .daily : .everyDays(count)
            return true
        }
        let list = "\(PhraseParser.englishWeekdays)((\\s*(,|and|&)\\s*)\(PhraseParser.englishWeekdays))*"
        take("(every|on) \(list)", text, &state) { m, s in
            guard let whole = Range(m.range, in: text) else { return false }
            let matched = String(text[whole])
            let skipped: Set<String> = ["every", "on", "and"]
            let pieces: [String] = matched.split(whereSeparator: { !$0.isLetter }).map(String.init)
            let words = pieces.filter { !skipped.contains($0) }
            let days = words.compactMap(self.englishWeekday)
            guard !days.isEmpty else { return false }
            let plural = matched.contains("days") || matched.hasPrefix("every")
            guard plural else { return false }
            s.weekdays = Array(Set(days)).sorted()
            s.rule = .weekly(s.weekdays)
            return true
        }
        take("(every week|weekly)", text, &state) { _, s in s.rule = .weekly([]); return true }
        take("(?:on )?the (\\d{1,2})(?:st|nd|rd|th)? (?:of )?every month", text, &state) { m, s in
            guard let day = group(m, 1, text).flatMap(Int.init), (1...31).contains(day) else { return false }
            s.rule = .monthlyOnDay(day)
            return true
        }
        take("(every month|monthly)( on the (\\d{1,2})(?:st|nd|rd|th)?)?", text, &state) { m, s in
            s.rule = .monthlyOnDay(group(m, 3, text).flatMap(Int.init) ?? 0)
            return true
        }
        take("(every year|yearly|annually)(?: on)?( \(PhraseParser.englishMonths) (\\d{1,2})(?:st|nd|rd|th)?| (\\d{1,2})(?:st|nd|rd|th)? (?:of )?\(PhraseParser.englishMonths))?", text, &state) { m, s in
            let month = (group(m, 3, text) ?? group(m, 6, text)).flatMap(self.englishMonth)
            let day = (group(m, 4, text) ?? group(m, 5, text)).flatMap(Int.init)
            if let month, let day, (1...31).contains(day) {
                s.rule = .yearly(month: month, day: day)
                s.date = nextDate(month: month, day: day, year: nil)
            } else {
                s.rule = .yearly(month: 0, day: 0)
            }
            return true
        }
    }

    private func englishOffsets(_ text: String, _ state: inout State) {
        take("in (half an hour|an hour and a half)", text, &state) { m, s in
            let minutes = group(m, 1, text) == "half an hour" ? 30 : 90
            s.exact = now.addingTimeInterval(Double(minutes) * 60)
            return true
        }
        take("in \(PhraseParser.englishCount) (minutes?|mins?|hours?|hrs?|days?|weeks?|months?)", text, &state) { m, s in
            let unit = group(m, 2, text) ?? ""
            let count = group(m, 1, text).flatMap(englishNumber) ?? 1
            if unit.hasPrefix("min") {
                s.exact = now.addingTimeInterval(Double(count) * 60)
            } else if unit.hasPrefix("h") {
                s.exact = now.addingTimeInterval(Double(count) * 3600)
            } else if unit.hasPrefix("day") {
                s.dayOffset = count
            } else if unit.hasPrefix("week") {
                s.dayOffset = count * 7
            } else if let date = calendar.date(byAdding: .month, value: count, to: now) {
                s.date = LocalDate(date, in: calendar)
            }
            return true
        }
    }

    private func englishDates(_ text: String, _ state: inout State) {
        take("(the day after tomorrow)", text, &state) { _, s in s.dayOffset = 2; return true }
        take("(tomorrow)", text, &state) { _, s in s.dayOffset = 1; return true }
        take("(today)", text, &state) { _, s in s.dayOffset = 0; return true }
        take("(tonight)", text, &state) { _, s in
            s.dayOffset = 0
            s.dayPart = evening
            return true
        }
        take("(?:on )?\(PhraseParser.englishMonths) (\\d{1,2})(?:st|nd|rd|th)?(?:,? (\\d{4}))?", text, &state) { m, s in
            guard let month = group(m, 1, text).flatMap(self.englishMonth), let day = group(m, 2, text).flatMap(Int.init), (1...31).contains(day) else { return false }
            s.date = nextDate(month: month, day: day, year: group(m, 3, text).flatMap(Int.init))
            if case .yearly = s.rule {
                s.rule = .yearly(month: month, day: day)
            }
            return true
        }
        take("(?:on )?(?:the )?(\\d{1,2})(?:st|nd|rd|th)? (?:of )?\(PhraseParser.englishMonths)(?: (\\d{4}))?", text, &state) { m, s in
            guard let day = group(m, 1, text).flatMap(Int.init), let month = group(m, 2, text).flatMap(self.englishMonth), (1...31).contains(day) else { return false }
            s.date = nextDate(month: month, day: day, year: group(m, 3, text).flatMap(Int.init))
            if case .yearly = s.rule {
                s.rule = .yearly(month: month, day: day)
            }
            return true
        }
        take("(?:on |next |this )?\(PhraseParser.englishWeekdays)", text, &state) { m, s in
            guard s.rule == nil, let word = group(m, 1, text), let day = self.englishWeekday(word) else { return false }
            s.weekdays = [day]
            return true
        }
    }

    private func englishTimes(_ text: String, _ state: inout State) {
        let meridiem = "\\s?(am|pm|a\\.m\\.|p\\.m\\.)?"
        let clock = "(\\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)"
        let hourWord = "(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)"
        take("(?:at |by )?half past \(clock)\(meridiem)", text, &state) { m, s in
            englishClock(group(m, 1, text), minute: 30, before: false, group(m, 2, text), &s)
        }
        take("(?:at |by )?(?:a )?quarter (past|after|to|till|of) \(clock)\(meridiem)", text, &state) { m, s in
            englishClock(group(m, 2, text), minute: 15, before: !["past", "after"].contains(group(m, 1, text) ?? ""), group(m, 3, text), &s)
        }
        take("(at |by )?(\\d{1,2}|five|ten|twenty-five|twenty five|twenty) (minutes )?(past|after|to|till) \(clock)\(meridiem)", text, &state) { m, s in
            let word = group(m, 2, text) ?? ""
            // A bare «5 to 6» may be a range, digits count as minutes only after «at» or with «minutes».
            guard let minute = Int(word) ?? PhraseParser.englishMinutes[word], Int(word) == nil || group(m, 1, text) != nil || group(m, 3, text) != nil else { return false }
            return englishClock(group(m, 5, text), minute: minute, before: !["past", "after"].contains(group(m, 4, text) ?? ""), group(m, 6, text), &s)
        }
        take("(?:at |by )half \(clock)\(meridiem)", text, &state) { m, s in
            englishClock(group(m, 1, text), minute: 30, before: false, group(m, 2, text), &s)
        }
        take("(?:at |by )\(hourWord)(?: (oh five|fifteen|thirty|forty-five|forty five|twenty-five|twenty five|twenty|ten|forty|fifty))?(?: o'clock)?\(meridiem)", text, &state) { m, s in
            englishClock(group(m, 1, text), minute: PhraseParser.englishMinutes[group(m, 2, text) ?? ""] ?? 0, before: false, group(m, 3, text), &s)
        }
        take("\(hourWord) o'clock\(meridiem)", text, &state) { m, s in
            englishClock(group(m, 1, text), minute: 0, before: false, group(m, 2, text), &s)
        }
        take("(?:at |by )?(\\d{1,2}):(\\d{2})\(meridiem)", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), let minute = group(m, 2, text).flatMap(Int.init), hour < 24, minute < 60 else { return false }
            s.time = LocalTime(hour: englishHour(hour, group(m, 3, text)), minute: minute)
            s.meridiem = group(m, 3, text) != nil
            return true
        }
        take("(?:at |by )(\\d{1,2})(?: o'clock)?\(meridiem)", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), hour < 24 else { return false }
            s.time = LocalTime(hour: englishHour(hour, group(m, 2, text)), minute: 0)
            s.meridiem = group(m, 2, text) != nil
            return true
        }
        take("(\\d{1,2})\\s?(am|pm|a\\.m\\.|p\\.m\\.)", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), hour <= 12 else { return false }
            s.time = LocalTime(hour: englishHour(hour, group(m, 2, text)), minute: 0)
            s.meridiem = group(m, 2, text) != nil
            return true
        }
        take("(?:at )?noon", text, &state) { _, s in s.time = LocalTime(hour: 12, minute: 0); return true }
        take("(?:at )?midnight", text, &state) { _, s in s.time = LocalTime(hour: 0, minute: 0); return true }
        take("(?:in the |this )?morning", text, &state) { _, s in s.dayPart = morning; return true }
        take("(?:in the |this )?afternoon", text, &state) { _, s in s.dayPart = LocalTime(hour: 14, minute: 0); return true }
        take("(?:in the |this )?evening", text, &state) { _, s in s.dayPart = evening; return true }
        take("at night", text, &state) { _, s in s.dayPart = LocalTime(hour: 23, minute: 0); return true }
    }

    private func englishHour(_ hour: Int, _ meridiem: String?) -> Int {
        guard let meridiem else { return hour }
        if meridiem.hasPrefix("p") {
            return hour < 12 ? hour + 12 : hour
        }
        return hour == 12 ? 0 : hour
    }

    private static let englishHours = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12]
    private static let englishMinutes = ["oh five": 5, "five": 5, "ten": 10, "fifteen": 15, "twenty": 20, "twenty-five": 25, "twenty five": 25, "thirty": 30, "forty": 40, "forty-five": 45, "forty five": 45, "fifty": 50]

    private func englishClock(_ word: String?, minute: Int, before: Bool, _ meridiem: String?, _ s: inout State) -> Bool {
        guard let word, let hour = Int(word) ?? PhraseParser.englishHours[word], let time = PhraseParser.clock(hour, minute: minute, before: before) else { return false }
        s.time = LocalTime(hour: englishHour(time.hour, meridiem), minute: time.minute)
        s.meridiem = meridiem != nil
        return true
    }

    private func englishAlerts(_ text: String, _ state: inout State) {
        take("half an hour (before|ahead|early|in advance)", text, &state) { _, s in s.preAlerts.append(30); return true }
        take("\(PhraseParser.englishCount) (minutes?|mins?|hours?|days?|weeks?) (before|ahead|early|in advance)", text, &state) { m, s in
            let unit = group(m, 2, text) ?? ""
            let count = group(m, 1, text).flatMap(englishNumber) ?? 1
            if unit.hasPrefix("min") {
                s.preAlerts.append(count)
            } else if unit.hasPrefix("h") {
                s.preAlerts.append(count * 60)
            } else if unit.hasPrefix("day") {
                s.preAlerts.append(count * 1_440)
            } else {
                s.preAlerts.append(count * 10_080)
            }
            return true
        }
        take("in advance", text, &state) { _, _ in true }
    }

    private func englishFlags(_ text: String, _ state: inout State) {
        take("(urgent|urgently|important)", text, &state) { _, s in s.urgent = true; return true }
        take("(persistently|until (?:i do it|it's done|i mark it|done)|keep reminding me|nag me)", text, &state) { _, s in s.nag = true; return true }
    }

    private func englishPlace(_ word: String) -> String? {
        let plain = word.replacingOccurrences(of: "'s", with: "")
        return places.first { place in
            let name = place.lowercased()
            return name == word || name == plain
        }
    }

    private func englishPlaces(_ text: String, _ state: inout State) {
        guard !places.isEmpty else { return }
        let triggers = "when i('m| am| get| arrive| come| leave| go| head) (?:back )?(?:to |at |from |out of |home)?(?:the |my )?"
        take("\(triggers)([\\p{L}-]+)?(?: (?:or|and) (?:the |my )?([\\p{L}-]+))?", text, &state) { m, s in
            let verb = (group(m, 1, text) ?? "").trimmingCharacters(in: .whitespaces)
            var words = [group(m, 2, text), group(m, 3, text)].compactMap { $0 }
            if let whole = Range(m.range, in: text), text[whole].contains("home") {
                words.append("home")
            }
            let found = words.compactMap(englishPlace)
            guard !found.isEmpty else { return false }
            s.placeTrigger = ["leave", "go", "head"].contains(verb) ? .leave : .arrive
            s.placeNames = Array(Set(found)).sorted()
            return true
        }
    }
}
