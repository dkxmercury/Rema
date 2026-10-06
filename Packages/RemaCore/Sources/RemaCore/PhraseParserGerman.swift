import Foundation

extension PhraseParser {
    private static let deMonths = "(januar|jänner|februar|märz|april|mai|juni|juli|august|september|oktober|november|dezember|jan|feb|mär|apr|jun|jul|aug|sep|sept|okt|nov|dez)\\.?"
    private static let deWeekdays = "(montags?|mo|dienstags?|di|mittwochs?|mi|donnerstags?|do|freitags?|fr|samstags?|sa|sonnabends?|sonntags?|so)"
    static let deWeekdaysFull = "(montags?|dienstags?|mittwochs?|donnerstags?|freitags?|samstags?|sonnabends?|sonntags?)"
    private static let deCount = "(\\d+|einer|einem|einen|eine|ein|zwei|drei|vier|fünf|zehn|fünfzehn|zwanzig|dreißig)"
    private static let deFillers: Set<String> = ["bitte"]
    private static let deLead: Set<String> = ["erinnere", "erinner", "mich", "daran", "zu", "ich", "muss", "soll", "bitte"]
    private static let deDangling: Set<String> = ["am", "um", "an", "in", "im", "zu", "zum", "zur", "und", "der", "die", "das", "den", "dem", "von", "für", "ab"]

    func parseGerman(_ input: String) -> ParsedPhrase {
        let text = input.lowercased().replacingOccurrences(of: "’", with: "'")
        var state = State()

        extras(text, &state, PhraseParser.germanExtras, weekday: deWeekday)
        deRepeats(text, &state)
        deOffsets(text, &state)
        deDates(text, &state)
        deTimes(text, &state)
        deAlerts(text, &state)
        deFlags(text, &state)
        dePlaces(text, &state)

        let schedule = resolve(&state)
        return ParsedPhrase(
            title: title(input, used: state.used, fillers: PhraseParser.deFillers, dangling: PhraseParser.deDangling, lead: PhraseParser.deLead),
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

    private func deWeekday(_ word: String) -> Weekday? {
        if word.hasPrefix("mo") { return .monday }
        if word.hasPrefix("di") { return .tuesday }
        if word.hasPrefix("mi") { return .wednesday }
        if word.hasPrefix("do") { return .thursday }
        if word.hasPrefix("fr") { return .friday }
        if word.hasPrefix("sa") || word.hasPrefix("sonnabend") { return .saturday }
        if word.hasPrefix("so") { return .sunday }
        return nil
    }

    private func deMonth(_ word: String) -> Int? {
        let stems = ["jan", "feb", "mär", "apr", "mai", "jun", "jul", "aug", "sep", "okt", "nov", "dez"]
        if word.hasPrefix("jän") { return 1 }
        return stems.firstIndex { word.hasPrefix($0) }.map { $0 + 1 }
    }

    private func deNumber(_ word: String) -> Int? {
        if let value = Int(word) { return value }
        switch word {
        case "ein", "eine", "einer", "einem", "einen": return 1
        case "zwei": return 2
        case "drei": return 3
        case "vier": return 4
        case "fünf": return 5
        case "zehn": return 10
        case "fünfzehn": return 15
        case "zwanzig": return 20
        case "dreißig": return 30
        default: return nil
        }
    }

    private func deRepeats(_ text: String, _ state: inout State) {
        take("(jeden tag|täglich)", text, &state) { _, s in s.rule = .daily; return true }
        take("(werktags|an werktagen|jeden werktag)", text, &state) { _, s in s.rule = .weekdays; return true }
        take("alle (\\d+) tage", text, &state) { m, s in
            guard let count = group(m, 1, text).flatMap(Int.init), count > 0 else { return false }
            s.rule = count == 1 ? .daily : .everyDays(count)
            return true
        }
        let list = "\(PhraseParser.deWeekdays)((\\s*(,|und|&)\\s*)\(PhraseParser.deWeekdays))*"
        take("(?:(jeden|jeder|jede) )?\(list)", text, &state) { m, s in
            guard let whole = Range(m.range, in: text) else { return false }
            let matched = String(text[whole])
            let pieces: [String] = matched.split(whereSeparator: { !$0.isLetter }).map(String.init)
            let days = pieces.filter { $0 != "jeden" && $0 != "jeder" && $0 != "jede" && $0 != "und" }.compactMap(self.deWeekday)
            let plural: Set<String> = ["montags", "dienstags", "mittwochs", "donnerstags", "freitags", "samstags", "sonnabends", "sonntags"]
            let repeating = matched.hasPrefix("jede") || pieces.contains { plural.contains($0) }
            guard !days.isEmpty, repeating else { return false }
            s.weekdays = Array(Set(days)).sorted()
            s.rule = .weekly(s.weekdays)
            return true
        }
        take("(jede woche|wöchentlich)", text, &state) { _, s in s.rule = .weekly([]); return true }
        take("(jeden monat|monatlich)( am (\\d{1,2})\\.?)?", text, &state) { m, s in
            s.rule = .monthlyOnDay(group(m, 3, text).flatMap(Int.init) ?? 0)
            return true
        }
        take("(jedes jahr|jährlich)( am (\\d{1,2})\\.? \(PhraseParser.deMonths))?", text, &state) { m, s in
            if let day = group(m, 3, text).flatMap(Int.init), let month = group(m, 4, text).flatMap(self.deMonth), (1...31).contains(day) {
                s.rule = .yearly(month: month, day: day)
                s.date = nextDate(month: month, day: day, year: nil)
            } else {
                s.rule = .yearly(month: 0, day: 0)
            }
            return true
        }
    }

    private func deOffsets(_ text: String, _ state: inout State) {
        take("in einer (halben stunde|dreiviertelstunde)", text, &state) { m, s in
            let minutes = group(m, 1, text) == "halben stunde" ? 30 : 45
            s.exact = now.addingTimeInterval(Double(minutes) * 60)
            return true
        }
        take("in \(PhraseParser.deCount) (minuten|minute|min|stunden|stunde|std|tagen|tag|wochen|woche|monaten|monat)", text, &state) { m, s in
            let unit = group(m, 2, text) ?? ""
            let count = group(m, 1, text).flatMap(deNumber) ?? 1
            if unit.hasPrefix("min") {
                s.exact = now.addingTimeInterval(Double(count) * 60)
            } else if unit.hasPrefix("st") {
                s.exact = now.addingTimeInterval(Double(count) * 3600)
            } else if unit.hasPrefix("tag") {
                s.dayOffset = count
            } else if unit.hasPrefix("woch") {
                s.dayOffset = count * 7
            } else if let date = calendar.date(byAdding: .month, value: count, to: now) {
                s.date = LocalDate(date, in: calendar)
            }
            return true
        }
    }

    private func deDates(_ text: String, _ state: inout State) {
        take("(übermorgen)", text, &state) { _, s in s.dayOffset = 2; return true }
        take("(morgen früh)", text, &state) { _, s in
            s.dayOffset = 1
            s.dayPart = morning
            return true
        }
        take("(heute abend)", text, &state) { _, s in
            s.dayOffset = 0
            s.dayPart = evening
            return true
        }
        take("(morgen abend)", text, &state) { _, s in
            s.dayOffset = 1
            s.dayPart = evening
            return true
        }
        take("(morgen)", text, &state) { _, s in s.dayOffset = 1; return true }
        take("(heute)", text, &state) { _, s in s.dayOffset = 0; return true }
        take("(?:am )?(\\d{1,2})\\.? \(PhraseParser.deMonths)(?: (\\d{4}))?", text, &state) { m, s in
            guard let day = group(m, 1, text).flatMap(Int.init), let month = group(m, 2, text).flatMap(self.deMonth), (1...31).contains(day) else { return false }
            s.date = nextDate(month: month, day: day, year: group(m, 3, text).flatMap(Int.init))
            if case .yearly = s.rule {
                s.rule = .yearly(month: month, day: day)
            }
            return true
        }
        take("(?:am |nächsten |kommenden )?\(PhraseParser.deWeekdaysFull)", text, &state) { m, s in
            guard s.rule == nil, let word = group(m, 1, text), let day = self.deWeekday(word) else { return false }
            s.weekdays = [day]
            return true
        }
    }

    private func deTimes(_ text: String, _ state: inout State) {
        take("(?:um |gegen |ab )?(\\d{1,2})[:.](\\d{2})(?: uhr)?", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), let minute = group(m, 2, text).flatMap(Int.init), hour < 24, minute < 60 else { return false }
            s.time = LocalTime(hour: hour, minute: minute)
            return true
        }
        take("(?:(?:um |gegen )(\\d{1,2})(?: uhr)?|(\\d{1,2}) uhr)", text, &state) { m, s in
            guard let hour = (group(m, 1, text) ?? group(m, 2, text)).flatMap(Int.init), hour < 24 else { return false }
            s.time = LocalTime(hour: hour, minute: 0)
            return true
        }
        take("(?:um )?(mittag|mittags)", text, &state) { _, s in s.time = LocalTime(hour: 12, minute: 0); return true }
        take("(?:um )?mitternacht", text, &state) { _, s in s.time = LocalTime(hour: 0, minute: 0); return true }
        take("(morgens|früh|am morgen|vormittags)", text, &state) { _, s in s.dayPart = morning; return true }
        take("(nachmittags|am nachmittag)", text, &state) { _, s in s.dayPart = LocalTime(hour: 14, minute: 0); return true }
        take("(abends|am abend)", text, &state) { _, s in s.dayPart = evening; return true }
        take("(nachts|in der nacht)", text, &state) { _, s in s.dayPart = LocalTime(hour: 23, minute: 0); return true }
    }

    private func deAlerts(_ text: String, _ state: inout State) {
        take("eine halbe stunde (vorher|davor|früher)", text, &state) { _, s in s.preAlerts.append(30); return true }
        take("\(PhraseParser.deCount) (minuten|minute|stunden|stunde|tage|tag|wochen|woche) (vorher|davor|früher)", text, &state) { m, s in
            let unit = group(m, 2, text) ?? ""
            let count = group(m, 1, text).flatMap(deNumber) ?? 1
            if unit.hasPrefix("min") {
                s.preAlerts.append(count)
            } else if unit.hasPrefix("st") {
                s.preAlerts.append(count * 60)
            } else if unit.hasPrefix("tag") {
                s.preAlerts.append(count * 1_440)
            } else {
                s.preAlerts.append(count * 10_080)
            }
            return true
        }
        take("(vorab|im voraus)", text, &state) { _, _ in true }
    }

    private func deFlags(_ text: String, _ state: inout State) {
        take("(dringend|wichtig)", text, &state) { _, s in s.urgent = true; return true }
        take("(beharrlich|bis ich es (?:erledige|abhake))", text, &state) { _, s in s.nag = true; return true }
    }

    private func dePlaces(_ text: String, _ state: inout State) {
        guard !places.isEmpty else { return }
        take("wenn ich nach hause (?:komme|gehe|fahre)", text, &state) { _, s in
            guard let home = places.first(where: { ["zuhause", "zu hause", "home", "haus", "daheim"].contains($0.lowercased()) }) else { return false }
            s.placeTrigger = .arrive
            s.placeNames = [home]
            return true
        }
        take("wenn ich (?:von |aus )(?:der |dem |den )?([\\p{L}-]+) (?:weggehe|losgehe|gehe|fahre|komme)", text, &state) { m, s in
            guard let word = group(m, 1, text), let place = dePlace(word) else { return false }
            s.placeTrigger = .leave
            s.placeNames = [place]
            return true
        }
        take("wenn ich (?:die |das |den )?([\\p{L}-]+) verlasse", text, &state) { m, s in
            guard let word = group(m, 1, text), let place = dePlace(word) else { return false }
            s.placeTrigger = .leave
            s.placeNames = [place]
            return true
        }
        take("wenn ich (?:zur |zum |in die |ins |in den |im |in der |bei |beim )?([\\p{L}-]+) (?:komme|ankomme|bin)", text, &state) { m, s in
            guard let word = group(m, 1, text), let place = dePlace(word) else { return false }
            s.placeTrigger = .arrive
            s.placeNames = [place]
            return true
        }
    }

    private func dePlace(_ word: String) -> String? {
        places.first { place in
            let name = place.lowercased()
            return name == word || name == word + "e" || name + "s" == word || name + "es" == word
        }
    }
}
