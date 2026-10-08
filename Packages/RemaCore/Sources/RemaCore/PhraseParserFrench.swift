import Foundation

extension PhraseParser {
    private static let frMonths = "(janvier|février|fevrier|mars|avril|mai|juin|juillet|août|aout|septembre|octobre|novembre|décembre|decembre|janv|févr|fevr|avr|juil|sept|oct|nov|déc|dec)\\.?"
    static let frWeekdays = "(lundis?|mardis?|mercredis?|jeudis?|vendredis?|samedis?|dimanches?)"
    private static let frCount = "(\\d{1,4}|une|un|deux|trois|quatre|cinq|dix|quinze|vingt|trente)"
    private static let frFillers: Set<String> = ["svp", "stp"]
    private static let frLead: Set<String> = ["rappelle-moi", "rappelle", "rappelez-moi", "moi", "de", "d'", "il", "faut", "je", "dois", "penser", "à"]
    private static let frDangling: Set<String> = ["à", "a", "le", "la", "les", "l'", "de", "du", "des", "d'", "et", "au", "aux", "en", "pour", "dans", "sur"]

    func parseFrench(_ input: String) -> ParsedPhrase {
        let text = input.lowercased().replacingOccurrences(of: "’", with: "'")
        func pass(_ text: String, _ state: inout State) {
            extras(text, &state, PhraseParser.frenchExtras, weekday: frWeekday)
            frRepeats(text, &state)
            frOffsets(text, &state)
            frDates(text, &state)
            frAlerts(text, &state)
            frTimes(text, &state)
            frFlags(text, &state)
            frPlaces(text, &state)
        }
        var state = corrected(text, PhraseParser.frenchCorrection, pass)

        let schedule = resolve(&state)
        var name = title(input, used: state.used + matches(",? ?(?:rappelle-moi|rappelez-moi|rappelle moi)", in: text).compactMap { span($0, text) }, fillers: PhraseParser.frFillers, dangling: PhraseParser.frDangling, lead: PhraseParser.frLead)
        for prefix in ["D'", "D’", "De "] where name.hasPrefix(prefix) {
            let rest = name.dropFirst(prefix.count)
            name = (rest.first.map { String($0).uppercased() } ?? "") + rest.dropFirst()
            break
        }
        return ParsedPhrase(
            title: name,
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
            corrected: state.corrected
        )
    }

    private func frWeekday(_ word: String) -> Weekday? {
        if word.hasPrefix("lun") { return .monday }
        if word.hasPrefix("mar") { return .tuesday }
        if word.hasPrefix("mer") { return .wednesday }
        if word.hasPrefix("jeu") { return .thursday }
        if word.hasPrefix("ven") { return .friday }
        if word.hasPrefix("sam") { return .saturday }
        if word.hasPrefix("dim") { return .sunday }
        return nil
    }

    private func frMonth(_ word: String) -> Int? {
        if word.hasPrefix("janv") { return 1 }
        if word.hasPrefix("fév") || word.hasPrefix("fev") { return 2 }
        if word.hasPrefix("mars") { return 3 }
        if word.hasPrefix("avr") { return 4 }
        if word.hasPrefix("mai") { return 5 }
        if word.hasPrefix("juin") { return 6 }
        if word.hasPrefix("juil") { return 7 }
        if word.hasPrefix("ao") { return 8 }
        if word.hasPrefix("sept") { return 9 }
        if word.hasPrefix("oct") { return 10 }
        if word.hasPrefix("nov") { return 11 }
        if word.hasPrefix("déc") || word.hasPrefix("dec") { return 12 }
        return nil
    }

    private func frNumber(_ word: String) -> Int? {
        if let value = Int(word) { return value }
        switch word {
        case "un", "une": return 1
        case "deux": return 2
        case "trois": return 3
        case "quatre": return 4
        case "cinq": return 5
        case "dix": return 10
        case "quinze": return 15
        case "vingt": return 20
        case "trente": return 30
        default: return nil
        }
    }

    private func frRepeats(_ text: String, _ state: inout State) {
        take("(tous les jours de semaine|tous les jours ouvrés|chaque jour ouvré|chaque jour de semaine|en semaine|les jours de semaine|les jours ouvrés)", text, &state) { _, s in s.rule = .weekdays; return true }
        take("(chaque matin|tous les matins)", text, &state) { _, s in s.rule = .daily; s.dayPart = morning; return true }
        take("(chaque soir|tous les soirs)", text, &state) { _, s in s.rule = .daily; s.dayPart = evening; return true }
        take("(tous les jours|chaque jour|quotidiennement)", text, &state) { _, s in s.rule = .daily; return true }
        take("tous les (\\d{1,4}) jours", text, &state) { m, s in
            guard let count = group(m, 1, text).flatMap(Int.init), count > 0 else { return false }
            s.rule = count == 1 ? .daily : .everyDays(count)
            return true
        }
        let list = "\(PhraseParser.frWeekdays)((\\s*(,|et)\\s*)\(PhraseParser.frWeekdays))*"
        take("(tous les|chaque|les|le) \(list)", text, &state) { m, s in
            guard let whole = Range(m.range, in: text) else { return false }
            let matched = String(text[whole])
            let pieces: [String] = matched.split(whereSeparator: { !$0.isLetter }).map(String.init)
            let days = pieces.compactMap(self.frWeekday)
            let repeating = matched.hasPrefix("tous") || matched.hasPrefix("chaque") || pieces.contains { $0.hasSuffix("s") && self.frWeekday($0) != nil && $0 != "mars" }
            guard !days.isEmpty, repeating else { return false }
            s.weekdays = Array(Set(days)).sorted()
            s.rule = .weekly(s.weekdays)
            return true
        }
        take("(chaque semaine|toutes les semaines|hebdomadaire)", text, &state) { _, s in s.rule = .weekly([]); return true }
        take("(tous les mois|chaque mois|mensuellement)( le (\\d{1,2}))?", text, &state) { m, s in
            s.rule = .monthlyOnDay(group(m, 3, text).flatMap(Int.init) ?? 0)
            return true
        }
        take("(tous les ans|chaque année|chaque annee|annuellement)( le (\\d{1,2})(?:er)? \(PhraseParser.frMonths))?", text, &state) { m, s in
            if let day = group(m, 3, text).flatMap(Int.init), let month = group(m, 4, text).flatMap(self.frMonth), (1...31).contains(day) {
                s.rule = .yearly(month: month, day: day)
                s.date = nextDate(month: month, day: day, year: nil)
            } else {
                s.rule = .yearly(month: 0, day: 0)
            }
            return true
        }
    }

    private func frOffsets(_ text: String, _ state: inout State) {
        take("dans (une demi-heure|une heure et demie)", text, &state) { m, s in
            let minutes = group(m, 1, text) == "une demi-heure" ? 30 : 90
            s.exact = now.addingTimeInterval(Double(minutes) * 60)
            return true
        }
        take("dans \(PhraseParser.frCount) (minutes?|min|heures?|h|jours?|semaines?|mois)", text, &state) { m, s in
            let unit = group(m, 2, text) ?? ""
            let count = group(m, 1, text).flatMap(frNumber) ?? 1
            if unit.hasPrefix("min") {
                s.exact = now.addingTimeInterval(Double(count) * 60)
            } else if unit.hasPrefix("h") {
                s.exact = now.addingTimeInterval(Double(count) * 3600)
            } else if unit.hasPrefix("jour") {
                s.dayOffset = count
            } else if unit.hasPrefix("sem") {
                s.dayOffset = count * 7
            } else if let date = calendar.date(byAdding: .month, value: count, to: now) {
                s.date = LocalDate(date, in: calendar)
            }
            return true
        }
    }

    private func frDates(_ text: String, _ state: inout State) {
        take("(après-demain|apres-demain)", text, &state) { _, s in s.dayOffset = 2; return true }
        take("(demain)", text, &state) { _, s in s.dayOffset = 1; return true }
        take("(aujourd'hui)", text, &state) { _, s in s.dayOffset = 0; return true }
        take("(ce soir)", text, &state) { _, s in
            s.dayOffset = 0
            s.dayPart = evening
            return true
        }
        take("(?:le )?(\\d{1,2})(?:er)? \(PhraseParser.frMonths)(?: (\\d{4}))?", text, &state) { m, s in
            guard let day = group(m, 1, text).flatMap(Int.init), let month = group(m, 2, text).flatMap(self.frMonth), (1...31).contains(day) else { return false }
            s.date = nextDate(month: month, day: day, year: group(m, 3, text).flatMap(Int.init))
            if case .yearly = s.rule {
                s.rule = .yearly(month: month, day: day)
            }
            return true
        }
        take("\(PhraseParser.frWeekdays)(?: prochain)?", text, &state) { m, s in
            guard s.rule == nil || s.rule == .weekly([]), let word = group(m, 1, text), let day = self.frWeekday(word) else { return false }
            s.weekdays = [day]
            s.nextWeek = saysNext(m, text)
            return true
        }
    }

    private func frTimes(_ text: String, _ state: inout State) {
        let part = "( du matin| du soir| de l'après-midi| de l'apres-midi)?"
        let words = "vingt et une|vingt-et-une|vingt-deux|vingt-trois|vingt|dix-sept|dix-huit|dix-neuf|dix|une|deux|trois|quatre|cinq|six|sept|huit|neuf|onze|douze|treize|quatorze|quinze|seize"
        let fraction = "( et demie?| et quart| moins le quart| moins quart| moins (cinq|dix|vingt-cinq|vingt|\\d{1,2}))"
        let about = "(?:environ|à peu près|a peu pres|aux alentours de|autour de|vers les)"
        take("\(about) (?:à |a )?(\\d{1,2}) ?(?:h|heures?)(?: ?(\\d{2}))?\(part)", text, &state) { m, s in
            frenchClock(group(m, 1, text), minute: group(m, 2, text).flatMap(Int.init) ?? 0, before: false, group(m, 3, text), &s)
        }
        take("\(about) (?:à |a )?(\(words)) heures?\(part)", text, &state) { m, s in
            frenchClock(group(m, 1, text), minute: 0, before: false, group(m, 2, text), &s)
        }
        take("(?:à |a |vers )?(\\d{1,2}|\(words)) ?(?:h|heures?)(?: ?(\\d{2}))?\(part) environ", text, &state) { m, s in
            frenchClock(group(m, 1, text), minute: group(m, 2, text).flatMap(Int.init) ?? 0, before: false, group(m, 3, text), &s)
        }
        take("(?:entre (\\d{1,2}) ?(?:h|heures?)?(?: ?(\\d{2}))? et|de (\\d{1,2}) ?(?:h|heures?)(?: ?(\\d{2}))? à) \\d{1,2} ?(?:h|heures?)(?: ?\\d{2})?\(part)", text, &state) { m, s in
            frenchClock(group(m, 1, text) ?? group(m, 3, text), minute: (group(m, 2, text) ?? group(m, 4, text)).flatMap(Int.init) ?? 0, before: false, group(m, 5, text), &s)
        }
        take("(?:à |a |vers )(\\d{1,2}|\(words)) ?(?:h|heures?)\(fraction)\(part)", text, &state) { m, s in
            frenchFraction(group(m, 1, text), group(m, 2, text), group(m, 3, text), group(m, 4, text), &s)
        }
        take("(?:à |a |vers )?(midi|minuit)\(fraction)", text, &state) { m, s in
            frenchFraction(group(m, 1, text), group(m, 2, text), group(m, 3, text), nil, &s)
        }
        take("(?:à |a |vers )(\(words)) heures?(?: (cinq|dix|quinze|vingt-cinq|vingt|trente|quarante-cinq|quarante|cinquante))?\(part)", text, &state) { m, s in
            frenchClock(group(m, 1, text), minute: PhraseParser.frenchMinutes[group(m, 2, text) ?? ""] ?? 0, before: false, group(m, 3, text), &s)
        }
        take("(?:à |de )?(\\d{1,2}) ?h(\\d{2})? ?[-–] ?\\d{1,2} ?h(?:\\d{2})?\(part)", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), hour < 24 else { return false }
            s.time = LocalTime(hour: frHour(hour, group(m, 3, text)), minute: group(m, 2, text).flatMap(Int.init) ?? 0)
            s.meridiem = group(m, 3, text) != nil
            return true
        }
        take("(?:à |a |vers )?(\\d{1,2}) ?(?:h|:) ?(\\d{2})\(part)", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), let minute = group(m, 2, text).flatMap(Int.init), hour < 24, minute < 60 else { return false }
            s.time = LocalTime(hour: frHour(hour, group(m, 3, text)), minute: minute)
            s.meridiem = group(m, 3, text) != nil || PhraseParser.twentyFour(group(m, 1, text))
            return true
        }
        // «Pendant 2 heures» and «4h de route» are durations, not a time of day.
        take("(?<!pendant |durant |en |dans |pour |de |il y a )(?:à |a |vers )?(\\d{1,2}) ?(?:h|heures?)\(part)(?! de | d')", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), hour < 24 else { return false }
            s.time = LocalTime(hour: frHour(hour, group(m, 2, text)), minute: 0)
            s.meridiem = group(m, 2, text) != nil
            return true
        }
        take("(?:à|vers) (\\d{1,2})(?! (?:(?:euros?|km|kg|personnes|minutes?|heures?|jours?|pour cent|ans|fois)(?![\\p{L}])|%))", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), hour < 24 else { return false }
            s.time = LocalTime(hour: hour, minute: 0)
            return true
        }
        take("(?<!après-|apres-|après |apres )(?:à |a )?midi", text, &state) { _, s in s.time = LocalTime(hour: 12, minute: 0); s.meridiem = true; return true }
        take("(?:à |a )?minuit", text, &state) { _, s in s.time = LocalTime(hour: 0, minute: 0); return true }
        take("(le matin|ce matin|au matin|matin)", text, &state) { _, s in s.dayPart = morning; return true }
        take("(l'après-midi|l'apres-midi|cet après-midi|cet apres-midi|après-midi|apres-midi|après midi|apres midi)", text, &state) { _, s in s.dayPart = LocalTime(hour: 14, minute: 0); return true }
        take("(le soir|au soir|soir)", text, &state) { _, s in s.dayPart = evening; return true }
        take("(la nuit|cette nuit)", text, &state) { _, s in s.dayPart = LocalTime(hour: 23, minute: 0); return true }
    }

    private func frHour(_ hour: Int, _ part: String?) -> Int {
        guard let part else { return hour }
        if part.contains("soir") || part.contains("midi") {
            return hour < 12 ? hour + 12 : hour
        }
        return hour == 12 ? 0 : hour
    }

    private static let frenchHours = ["une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10, "onze": 11, "douze": 12, "midi": 12, "treize": 13, "quatorze": 14, "quinze": 15, "seize": 16, "dix-sept": 17, "dix-huit": 18, "dix-neuf": 19, "vingt": 20, "vingt et une": 21, "vingt-et-une": 21, "vingt-deux": 22, "vingt-trois": 23]
    private static let frenchMinutes = ["cinq": 5, "dix": 10, "quinze": 15, "vingt": 20, "vingt-cinq": 25, "trente": 30, "quarante": 40, "quarante-cinq": 45, "cinquante": 50]

    private func frenchClock(_ word: String?, minute: Int, before: Bool, _ part: String?, _ s: inout State) -> Bool {
        guard let word, let hour = word == "minuit" ? (before ? 24 : 0) : Int(word) ?? PhraseParser.frenchHours[word], let time = PhraseParser.clock(hour, minute: minute, before: before) else { return false }
        s.time = LocalTime(hour: frHour(time.hour, part), minute: time.minute)
        s.meridiem = part != nil || word == "midi" || word == "minuit"
        return true
    }

    private func frenchFraction(_ hour: String?, _ fraction: String?, _ count: String?, _ part: String?, _ s: inout State) -> Bool {
        guard let fraction else { return false }
        if fraction.contains("demi") { return frenchClock(hour, minute: 30, before: false, part, &s) }
        if fraction.contains("et quart") { return frenchClock(hour, minute: 15, before: false, part, &s) }
        if fraction.contains("quart") { return frenchClock(hour, minute: 15, before: true, part, &s) }
        guard let count, let minute = Int(count) ?? PhraseParser.frenchMinutes[count] else { return false }
        return frenchClock(hour, minute: minute, before: true, part, &s)
    }

    private func frAlerts(_ text: String, _ state: inout State) {
        take("(la veille)", text, &state) { _, s in s.preAlerts.append(1_440); return true }
        take("une demi-heure avant", text, &state) { _, s in s.preAlerts.append(30); return true }
        take("\(PhraseParser.frCount) (minutes?|heures?|jours?|semaines?) (avant|à l'avance|plus tôt)", text, &state) { m, s in
            let unit = group(m, 2, text) ?? ""
            let count = group(m, 1, text).flatMap(frNumber) ?? 1
            if unit.hasPrefix("min") {
                s.preAlerts.append(count)
            } else if unit.hasPrefix("h") {
                s.preAlerts.append(count * 60)
            } else if unit.hasPrefix("jour") {
                s.preAlerts.append(count * 1_440)
            } else {
                s.preAlerts.append(count * 10_080)
            }
            return true
        }
        take("(à l'avance|a l'avance)", text, &state) { _, _ in true }
    }

    private func frFlags(_ text: String, _ state: inout State) {
        take("(très importante?|tres importante?|urgente?|importante?|absolument|sans faute|impérativement|imperativement)", text, &state) { _, s in s.urgent = true; return true }
        take("(?:ne (?:surtout )?pas oublier|surtout ne pas oublier|n'oubliez? pas)", text, &state) { _, _ in true }
        take("(avec insistance|jusqu'à ce que je le fasse|jusqu'à ce que je coche)", text, &state) { _, s in s.nag = true; return true }
    }

    private func frPlaces(_ text: String, _ state: inout State) {
        guard !places.isEmpty else { return }
        take("quand je rentre(?: à la maison| chez moi)?", text, &state) { m, s in
            guard let whole = Range(m.range, in: text), text[whole].contains("maison") || text[whole].contains("chez moi"),
                  let home = places.first(where: { ["maison", "domicile", "home", "chez moi"].contains($0.lowercased()) }) else { return false }
            s.placeTrigger = .arrive
            s.placeNames = [home]
            return true
        }
        take("quand (?:je pars|je sors) (?:du |de la |de l'|des |de )?([\\p{L}'-]+)", text, &state) { m, s in
            guard let word = group(m, 1, text), let place = frPlace(word) else { return false }
            s.placeTrigger = .leave
            s.placeNames = [place]
            return true
        }
        take("quand je quitte (?:le |la |l'|les )?([\\p{L}'-]+)", text, &state) { m, s in
            guard let word = group(m, 1, text), let place = frPlace(word) else { return false }
            s.placeTrigger = .leave
            s.placeNames = [place]
            return true
        }
        take("quand (?:j'arrive|je suis|je passe) (?:au |à la |à l'|aux |chez |à |a la |a )?([\\p{L}'-]+)", text, &state) { m, s in
            guard let word = group(m, 1, text), let place = frPlace(word) else { return false }
            s.placeTrigger = .arrive
            s.placeNames = [place]
            return true
        }
    }

    private func frPlace(_ word: String) -> String? {
        places.first { place in
            let name = place.lowercased()
            return name == word || name + "s" == word
        }
    }
}
