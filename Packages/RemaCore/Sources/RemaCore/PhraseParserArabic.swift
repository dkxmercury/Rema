import Foundation

extension PhraseParser {
    static let arMonths = "(يناير|فبراير|مارس|ابريل|مايو|يونيو|يوليو|اغسطس|سبتمبر|اكتوبر|نوفمبر|ديسمبر|شباط|اذار|نيسان|ايار|حزيران|تموز|اب|ايلول)"
    // «اثنين» and «احد» are also «two» and «one», as a day they need «يوم» or the article.
    static let arWeekday = "((?:يوم )?(?:ال)?(?:ثلاثاء|اربعاء|خميس|جمعة|جمعه|سبت)|(?:يوم (?:ال)?|ال)(?:اثنين|احد))"
    private static let arCount = "(\\d{1,4}|خمس عشرة|خمسة عشر|عشرين|ثلاثين|اربعين|خمسين|واحدة|واحد|ثلاثة|ثلاث|اربعة|اربع|خمسة|خمس|ستة|ست|سبعة|سبع|ثمانية|ثماني|تسعة|تسع|عشرة|عشر)"
    private static let arCounts = ["واحد": 1, "واحدة": 1, "ثلاث": 3, "ثلاثة": 3, "اربع": 4, "اربعة": 4, "خمس": 5, "خمسة": 5, "ست": 6, "ستة": 6, "سبع": 7, "سبعة": 7, "ثماني": 8, "ثمانية": 8, "تسع": 9, "تسعة": 9, "عشر": 10, "عشرة": 10, "خمس عشرة": 15, "خمسة عشر": 15, "عشرين": 20, "ثلاثين": 30, "اربعين": 40, "خمسين": 50]
    private static let arFillers: Set<String> = ["ذكرني", "ذكّرني", "فضلك", "رجاء", "رجاءً", "تقريبا", "تقريبًا"]
    private static let arLead: Set<String> = ["ان", "أن", "من", "يجب", "علي", "عليّ"]
    private static let arDangling: Set<String> = ["في", "عند", "و", "على", "من", "الى", "إلى", "ب", "ان", "أن"]

    static func looksArabic(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
    }

    static func arabicNormalized(_ text: String) -> (String, [Int]) {
        var output = ""
        var origin: [Int] = []
        for (index, character) in text.enumerated() {
            guard let scalar = character.unicodeScalars.first else { continue }
            let value = scalar.value
            if (0x064B...0x0652).contains(value) || value == 0x0640 || value == 0x0670 { continue }
            var mapped = String(character)
            switch value {
            case 0x0623, 0x0625, 0x0622: mapped = "ا"
            case 0x0649: mapped = "ي"
            case 0x060C: mapped = ","
            case 0x0660...0x0669: mapped = String(value - 0x0660)
            case 0x06F0...0x06F9: mapped = String(value - 0x06F0)
            default:
                let stripped = character.unicodeScalars.filter { !(0x064B...0x0652).contains($0.value) }
                mapped = String(String.UnicodeScalarView(stripped))
            }
            for symbol in mapped {
                output.append(symbol)
                origin.append(index)
            }
        }
        return (output, origin)
    }

    func parseArabic(_ input: String) -> ParsedPhrase {
        let (text, origin) = PhraseParser.arabicNormalized(input)
        func pass(_ text: String, _ state: inout State) {
            extras(text, &state, PhraseParser.arabicExtras, weekday: arWeekdayValue)
            arRepeats(text, &state)
            limits(text, &state, PhraseParser.arabicLimits, weekday: arWeekdayValue, month: arMonth)
            arOffsets(text, &state)
            arDates(text, &state)
            arTimes(text, &state)
            arAlerts(text, &state)
            arFlags(text, &state)
            arPlaces(text, &state)
        }
        var state = corrected(text, PhraseParser.arabicCorrection, pass)

        let schedule = resolve(&state)
        let used = state.used.compactMap { range -> Range<Int>? in
            guard !range.isEmpty, range.upperBound - 1 < origin.count else { return nil }
            return origin[range.lowerBound]..<(origin[range.upperBound - 1] + 1)
        }
        return ParsedPhrase(
            title: title(input, used: used, fillers: PhraseParser.arFillers, dangling: PhraseParser.arDangling, lead: PhraseParser.arLead),
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
            corrected: state.corrected
        )
    }

    private func arWeekdayValue(_ word: String) -> Weekday? {
        if word.contains("اثنين") { return .monday }
        if word.contains("ثلاثاء") { return .tuesday }
        if word.contains("اربعاء") { return .wednesday }
        if word.contains("خميس") { return .thursday }
        if word.contains("جمع") { return .friday }
        if word.contains("سبت") { return .saturday }
        if word.contains("احد") { return .sunday }
        return nil
    }

    private func arMonth(_ word: String) -> Int? {
        let names = [
            ["يناير"], ["فبراير", "شباط"], ["مارس", "اذار"], ["ابريل", "نيسان"], ["مايو", "ايار"], ["يونيو", "حزيران"],
            ["يوليو", "تموز"], ["اغسطس", "اب"], ["سبتمبر", "ايلول"], ["اكتوبر"], ["نوفمبر"], ["ديسمبر"],
        ]
        return names.firstIndex { $0.contains(word) }.map { $0 + 1 }
    }

    private func arUnit(_ word: String) -> (unit: String, count: Int)? {
        switch word {
        case "دقيقة", "دقائق", "دقيقه": return ("minute", 1)
        case "دقيقتين", "دقيقتان": return ("minute", 2)
        case "ساعة", "ساعات", "ساعه": return ("hour", 1)
        case "ساعتين", "ساعتان": return ("hour", 2)
        case "يوم", "ايام": return ("day", 1)
        case "يومين", "يومان": return ("day", 2)
        case "اسبوع", "اسابيع": return ("week", 1)
        case "اسبوعين", "اسبوعان": return ("week", 2)
        case "شهر", "اشهر", "شهور": return ("month", 1)
        case "شهرين", "شهران": return ("month", 2)
        default: return nil
        }
    }

    private static let arUnits = "(دقيقة|دقيقه|دقائق|دقيقتين|دقيقتان|ساعة|ساعه|ساعات|ساعتين|ساعتان|يوم|ايام|يومين|يومان|اسبوع|اسابيع|اسبوعين|اسبوعان|شهر|اشهر|شهور|شهرين|شهران)"

    private func arRepeats(_ text: String, _ state: inout State) {
        take("(كل يوم(?! (?:ال)?(?:اثنين|ثلاثاء|اربعاء|خميس|جمعة|جمعه|سبت|احد))|يوميا)", text, &state) { _, s in s.rule = .daily; return true }
        take("(ايام العمل|في ايام العمل)", text, &state) { _, s in s.rule = .weekdays; return true }
        take("كل (\\d{1,4}) (?:ايام|يوم)", text, &state) { m, s in
            guard let count = group(m, 1, text).flatMap(Int.init), count > 0 else { return false }
            s.rule = count == 1 ? .daily : .everyDays(count)
            return true
        }
        let list = "\(PhraseParser.arWeekday)((?:\\s*,?\\s*و\\s*|\\s*,\\s*)\(PhraseParser.arWeekday))*"
        take("كل \(list)", text, &state) { m, s in
            guard let whole = Range(m.range, in: text) else { return false }
            let pieces: [String] = String(text[whole]).split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
            let days = pieces.compactMap(self.arWeekdayValue)
            guard !days.isEmpty else { return false }
            s.weekdays = Array(Set(days)).sorted()
            s.rule = .weekly(s.weekdays)
            return true
        }
        take("(كل اسبوع|اسبوعيا)", text, &state) { _, s in s.rule = .weekly([]); return true }
        take("(كل شهر|شهريا)( في (\\d{1,2}))?", text, &state) { m, s in
            s.rule = .monthlyOnDay(group(m, 3, text).flatMap(Int.init) ?? 0)
            return true
        }
        take("(كل سنة|كل عام|سنويا)( في (\\d{1,2}) \(PhraseParser.arMonths))?", text, &state) { m, s in
            if let day = group(m, 3, text).flatMap(Int.init), let month = group(m, 4, text).flatMap(self.arMonth), (1...31).contains(day) {
                s.rule = .yearly(month: month, day: day)
                s.date = nextDate(month: month, day: day, year: nil)
            } else {
                s.rule = .yearly(month: 0, day: 0)
            }
            return true
        }
    }

    private func arOffsets(_ text: String, _ state: inout State) {
        take("بعد نصف ساعة", text, &state) { _, s in
            s.exact = now.addingTimeInterval(1_800)
            return true
        }
        take("بعد ربع ساعة", text, &state) { _, s in
            s.exact = now.addingTimeInterval(900)
            return true
        }
        take("بعد (?:\(PhraseParser.arCount) )?\(PhraseParser.arUnits)", text, &state) { m, s in
            guard let word = group(m, 2, text), let unit = self.arUnit(word) else { return false }
            let count = group(m, 1, text).flatMap { Int($0) ?? PhraseParser.arCounts[$0] } ?? unit.count
            switch unit.unit {
            case "minute": s.exact = now.addingTimeInterval(Double(count) * 60)
            case "hour": s.exact = now.addingTimeInterval(Double(count) * 3600)
            case "day": s.dayOffset = count
            case "week": s.dayOffset = count * 7
            default:
                if let date = calendar.date(byAdding: .month, value: count, to: now) {
                    s.date = LocalDate(date, in: calendar)
                }
            }
            return true
        }
    }

    private func arDates(_ text: String, _ state: inout State) {
        take("(بعد (?:ال)?غد)", text, &state) { _, s in s.dayOffset = 2; return true }
        take("(غدا|بكرة|بكره|(?:يوم )?الغد)", text, &state) { _, s in s.dayOffset = 1; return true }
        take("(هذا المساء|هذه الليلة|الليلة)", text, &state) { _, s in
            s.dayOffset = 0
            s.dayPart = evening
            return true
        }
        take("(اليوم)", text, &state) { _, s in s.dayOffset = 0; return true }
        take("(?:في )?(\\d{1,2}) \(PhraseParser.arMonths)(?: (\\d{4}))?", text, &state) { m, s in
            guard let day = group(m, 1, text).flatMap(Int.init), let month = group(m, 2, text).flatMap(self.arMonth), (1...31).contains(day) else { return false }
            s.date = nextDate(month: month, day: day, year: group(m, 3, text).flatMap(Int.init))
            if case .yearly = s.rule {
                s.rule = .yearly(month: month, day: day)
            }
            return true
        }
        take("(?:في )?\(PhraseParser.arWeekday)(?: القادم)?", text, &state) { m, s in
            guard s.rule == nil || s.rule == .weekly([]), let word = group(m, 1, text), let day = self.arWeekdayValue(word) else { return false }
            s.weekdays = [day]
            if s.rule == .weekly([]) {
                s.rule = .weekly([day])
            }
            return true
        }
    }

    private func arTimes(_ text: String, _ state: inout State) {
        let modifier = "(?: (صباحا|مساء|ظهرا|ليلا))?"
        let hourWords = "الحادية عشرة|الحادية عشر|الثانية عشرة|الثانية عشر|الواحدة|الثانية|الثالثة|الرابعة|الخامسة|السادسة|السابعة|الثامنة|التاسعة|العاشرة"
        let hours = "(\\d{1,2}|\(hourWords))"
        let count = "(?:خمس وعشرين|عشرين|عشر|خمس)(?: دقائق| دقيقة)?"
        let fraction = "(والنصف|والربع|والثلث|الا (?:ال)?ربعا?|الا (?:ال)?ثلثا?|و\(count)|الا \(count))"
        take("(?:حوالي|نحو|قرابة|تقريبا) (?:في )?(الساعة |الساعه )?\(hours)(?::(\\d{2}))?(?: \(fraction))?\(modifier)", text, &state) { m, s in
            // «حوالي 2 كيلو» is an amount, a bare number is an hour only with «الساعة».
            guard group(m, 2, text).flatMap(Int.init) == nil || group(m, 1, text) != nil || group(m, 3, text) != nil || group(m, 5, text) != nil else { return false }
            let part = arFraction(group(m, 4, text))
            return arClock(group(m, 2, text), minute: group(m, 3, text).flatMap(Int.init) ?? part.minute, before: part.before, group(m, 5, text), &s)
        }
        take("بين (?:الساعة |الساعه )?\(hours) و ?(?:الساعة |الساعه )?(?:\\d{1,2}|\(hourWords))\(modifier)", text, &state) { m, s in
            arClock(group(m, 1, text), minute: 0, before: false, group(m, 2, text), &s)
        }
        take("(?:الساعة |الساعه |في |عند )?(\\d{1,2}):(\\d{2})\(modifier)", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), let minute = group(m, 2, text).flatMap(Int.init), hour < 24, minute < 60 else { return false }
            s.time = LocalTime(hour: arHour(hour, group(m, 3, text)), minute: minute)
            s.meridiem = group(m, 3, text) != nil
            return true
        }
        take("(?:في |عند )?(?:الساعة|الساعه) \(hours)(?: \(fraction))?\(modifier)", text, &state) { m, s in
            let part = arFraction(group(m, 2, text))
            return arClock(group(m, 1, text), minute: part.minute, before: part.before, group(m, 3, text), &s)
        }
        take("(?:الساعة|الساعه|عند) (\\d{1,2})\(modifier)", text, &state) { m, s in
            guard let hour = group(m, 1, text).flatMap(Int.init), hour < 24 else { return false }
            s.time = LocalTime(hour: arHour(hour, group(m, 2, text)), minute: 0)
            s.meridiem = group(m, 2, text) != nil
            return true
        }
        take("(بعد الظهر|بعد الظهيرة|ظهرا)", text, &state) { _, s in s.dayPart = LocalTime(hour: 14, minute: 0); return true }
        take("(?:عند )?(الظهر|الظهيرة)", text, &state) { _, s in s.time = LocalTime(hour: 12, minute: 0); return true }
        take("(?:عند )?منتصف الليل", text, &state) { _, s in s.time = LocalTime(hour: 0, minute: 0); return true }
        take("(صباحا|في الصباح|صباح(?= (?:الغد|اليوم|غدا|يوم|ال(?:اثنين|ثلاثاء|اربعاء|خميس|جمعة|جمعه|سبت|احد))))", text, &state) { _, s in s.dayPart = morning; return true }
        take("(مساء|في المساء)", text, &state) { _, s in s.dayPart = evening; return true }
        take("(ليلا|في الليل)", text, &state) { _, s in s.dayPart = LocalTime(hour: 23, minute: 0); return true }
    }

    private static let arHours = ["الواحدة": 1, "الثانية": 2, "الثالثة": 3, "الرابعة": 4, "الخامسة": 5, "السادسة": 6, "السابعة": 7, "الثامنة": 8, "التاسعة": 9, "العاشرة": 10, "الحادية عشرة": 11, "الحادية عشر": 11, "الثانية عشرة": 12, "الثانية عشر": 12]

    private func arFraction(_ fraction: String?) -> (minute: Int, before: Bool) {
        guard let fraction else { return (0, false) }
        let minute = [("نصف", 30), ("ربع", 15), ("ثلث", 20), ("خمس وعشرين", 25), ("عشرين", 20), ("عشر", 10), ("خمس", 5)].first { fraction.contains($0.0) }?.1 ?? 0
        return (minute, fraction.hasPrefix("الا"))
    }

    private func arClock(_ word: String?, minute: Int, before: Bool, _ modifier: String?, _ s: inout State) -> Bool {
        guard let word, let hour = Int(word) ?? PhraseParser.arHours[word], let time = PhraseParser.clock(hour, minute: minute, before: before) else { return false }
        s.time = LocalTime(hour: arHour(time.hour, modifier), minute: time.minute)
        s.meridiem = modifier != nil
        return true
    }

    private func arHour(_ hour: Int, _ modifier: String?) -> Int {
        switch modifier {
        case "مساء", "ظهرا":
            return hour < 12 ? hour + 12 : hour
        case "صباحا":
            return hour == 12 ? 0 : hour
        case "ليلا":
            if hour == 12 { return 0 }
            return (6...11).contains(hour) ? hour + 12 : hour
        default:
            return hour
        }
    }

    private func arAlerts(_ text: String, _ state: inout State) {
        take("قبل نصف ساعة", text, &state) { _, s in s.preAlerts.append(30); return true }
        take("قبل ربع ساعة", text, &state) { _, s in s.preAlerts.append(15); return true }
        take("قبل (?:\(PhraseParser.arCount) )?\(PhraseParser.arUnits)", text, &state) { m, s in
            guard let word = group(m, 2, text), let unit = self.arUnit(word), unit.unit != "month" else { return false }
            let count = group(m, 1, text).flatMap { Int($0) ?? PhraseParser.arCounts[$0] } ?? unit.count
            switch unit.unit {
            case "minute": s.preAlerts.append(count)
            case "hour": s.preAlerts.append(count * 60)
            case "day": s.preAlerts.append(count * 1_440)
            default: s.preAlerts.append(count * 10_080)
            }
            return true
        }
        take("(مسبقا|مقدما)", text, &state) { _, _ in true }
    }

    private func arFlags(_ text: String, _ state: inout State) {
        take("(مهم جدا|عاجل|مهم|ضروري|بالتاكيد)", text, &state) { _, s in s.urgent = true; return true }
        take("(?:لا تنسوا|لا تنسي|لا تنس|تذكر(?: ان)?|لا بد(?: من| ان)?)", text, &state) { _, _ in true }
        take("(بالحاح|حتي انجزه|حتي اضع علامة)", text, &state) { _, s in s.nag = true; return true }
    }

    private func arPlaces(_ text: String, _ state: inout State) {
        guard !places.isEmpty else { return }
        take("عندما اعود الي (?:البيت|المنزل)", text, &state) { _, s in
            guard let home = places.first(where: { ["البيت", "المنزل", "بيت", "منزل"].contains(PhraseParser.arabicNormalized($0).0) }) else { return false }
            s.placeTrigger = .arrive
            s.placeNames = [home]
            return true
        }
        take("عندما (?:اغادر|اخرج من|اترك) (\\p{L}+)", text, &state) { m, s in
            guard let word = group(m, 1, text), let place = arPlace(word) else { return false }
            s.placeTrigger = .leave
            s.placeNames = [place]
            return true
        }
        take("عندما (?:اصل الي|اكون في|ادخل|اذهب الي) (\\p{L}+)", text, &state) { m, s in
            guard let word = group(m, 1, text), let place = arPlace(word) else { return false }
            s.placeTrigger = .arrive
            s.placeNames = [place]
            return true
        }
    }

    private func arPlace(_ word: String) -> String? {
        let bare = word.hasPrefix("ال") ? String(word.dropFirst(2)) : word
        return places.first { place in
            let name = PhraseParser.arabicNormalized(place).0
            let plain = name.hasPrefix("ال") ? String(name.dropFirst(2)) : name
            return plain == bare
        }
    }
}
