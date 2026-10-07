import Foundation

extension PhraseParser {
    private static let frMonths = "(janvier|février|fevrier|mars|avril|mai|juin|juillet|août|aout|septembre|octobre|novembre|décembre|decembre|janv|févr|fevr|avr|juil|sept|oct|nov|déc|dec)\\.?"
    static let frWeekdays = "(lundis?|mardis?|mercredis?|jeudis?|vendredis?|samedis?|dimanches?)"
    private static let frCount = "(\\d+|une|un|deux|trois|quatre|cinq|dix|quinze|vingt|trente)"
    private static let frFillers: Set<String> = ["svp", "stp"]
    private static let frLead: Set<String> = ["rappelle-moi", "rappelle", "rappelez-moi", "moi", "de", "d'", "il", "faut", "je", "dois", "penser", "à"]
    private static let frDangling: Set<String> = ["à", "a", "le", "la", "les", "l'", "de", "du", "des", "d'", "et", "au", "aux", "en", "pour", "dans", "sur"]

    func parseFrench(_ input: String) -> ParsedPhrase {
        let text = input.lowercased().replacingOccurrences(of: "’", with: "'")
        var state = State()

        extras(text, &state, PhraseParser.frenchExtras, weekday: frWeekday)
        frRepeats(text, &state)
        frOffsets(text, &state)
        frDates(text, &state)
        frTimes(text, &state)
        frAlerts(text, &state)
        frFlags(text, &state)
        frPlaces(text, &state)

        let schedule = resolve(&state)
        var name = title(input, used: state.used, fillers: PhraseParser.frFillers, dangling: PhraseParser.frDangling, lead: PhraseParser.frLead)
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
            alternative: state.alternative
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
        take("(tous les jours|chaque jour|quotidiennement)", text, &state) { _, s in s.rule = .daily; return true }
        take("(en semaine|les jours de semaine|chaque jour ouvré|les jours ouvrés)", text, &state) { _, s in s.rule = .weekdays; return true }
        take("tous les (\\d+) jours", text, &state) { m, s in
            guard let count = group(m, 1, text).flatMap(Int.init), count > 0 else { return false }
            s.rule = count == 1 ? .daily : .everyDays(count)
            return true
        }
        let list = "\(PhraseParser.frWeekdays)((\\s*(,|et)\\s*)\(PhraseParser.frWeekdays))*"
        take("(tous les|chaque|le) \(list)", text, &state) { m, s in
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
            guard s.rule == nil, let word = group(m, 1, text), let day = self.frWeekday(word) else { return false }
            s.weekdays = [day]
            return true
        }
    }

    private func frTimes(_ text: String, _ state: inout State) {
        let part = "( du matin| du soir| de l'après-midi| de l'apres-midi)?"
        take("(?:à |a |vers )?(\\d{1,2}) ?(?:h|:) ?(\\d{2})\(part)", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), let minute = group(m, 2, text).flatMap(Int.init), hour < 24, minute < 60 else { return false }
            s.time = LocalTime(hour: frHour(hour, group(m, 3, text)), minute: minute)
            s.meridiem = group(m, 3, text) != nil
            return true
        }
        take("(?:à |a |vers )?(\\d{1,2}) ?(?:h|heures?)\(part)", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), hour < 24 else { return false }
            s.time = LocalTime(hour: frHour(hour, group(m, 2, text)), minute: 0)
            s.meridiem = group(m, 2, text) != nil
            return true
        }
        take("(?:à|vers) (\\d{1,2})", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), hour < 24 else { return false }
            s.time = LocalTime(hour: hour, minute: 0)
            return true
        }
        take("(?:à |a )?midi", text, &state) { _, s in s.time = LocalTime(hour: 12, minute: 0); return true }
        take("(?:à |a )?minuit", text, &state) { _, s in s.time = LocalTime(hour: 0, minute: 0); return true }
        take("(le matin|ce matin|au matin|matin)", text, &state) { _, s in s.dayPart = morning; return true }
        take("(l'après-midi|l'apres-midi|cet après-midi|cet apres-midi)", text, &state) { _, s in s.dayPart = LocalTime(hour: 14, minute: 0); return true }
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
        take("(urgent|urgente|important|importante)", text, &state) { _, s in s.urgent = true; return true }
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
