import Foundation

extension PhraseParser {
    struct Extras {
        var lunch: String
        var afterWork: String
        var towardEvening: String
        var weekend: String
        var everyWeekend: String
        var monthEnd: String
        var everyMonthEnd: String
        var everyOtherDay: String
        var everyOtherWeekday: String
        var nthWeekday: String
        var ordinals: [(prefix: String, value: Int)]
    }

    // Runs before the language's own rules, so "every second Tuesday" is not read as a plain Tuesday.
    func extras(_ text: String, _ state: inout State, _ phrases: Extras, weekday: (String) -> Weekday?) {
        func groups(_ match: NSTextCheckingResult) -> [String] {
            (1..<match.numberOfRanges).compactMap { group(match, $0, text) }
        }

        func ordinal(_ word: String) -> Int? {
            phrases.ordinals.first { word.hasPrefix($0.prefix) }?.value
        }

        take(phrases.everyMonthEnd, text, &state) { _, s in
            s.rule = .monthlyOnDay(31)
            return true
        }
        take(phrases.nthWeekday, text, &state) { m, s in
            let words = groups(m)
            guard let count = words.compactMap(ordinal).first, let day = words.reversed().compactMap(weekday).first else { return false }
            s.rule = .monthlyOnWeekday(ordinal: count, weekday: day)
            return true
        }
        take(phrases.everyOtherWeekday, text, &state) { m, s in
            guard let day = groups(m).reversed().compactMap(weekday).first else { return false }
            s.weekdays = [day]
            s.rule = .everyDays(14)
            return true
        }
        take(phrases.everyOtherDay, text, &state) { _, s in
            s.rule = .everyDays(2)
            return true
        }
        take(phrases.everyWeekend, text, &state) { _, s in
            s.weekdays = [.saturday, .sunday]
            s.rule = .weekly([.saturday, .sunday])
            return true
        }
        take(phrases.weekend, text, &state) { _, s in
            guard s.rule == nil else { return false }
            s.weekdays = [.saturday, .sunday]
            return true
        }
        take(phrases.monthEnd, text, &state) { _, s in
            let today = LocalDate(now, in: calendar)
            s.date = LocalDate(year: today.year, month: today.month, day: LocalDate.days(in: today.month, year: today.year))
            return true
        }
        take(phrases.lunch, text, &state) { _, s in
            s.dayPart = LocalTime(hour: 13, minute: 0)
            return true
        }
        take(phrases.afterWork, text, &state) { _, s in
            s.dayPart = LocalTime(hour: 18, minute: 30)
            return true
        }
        take(phrases.towardEvening, text, &state) { _, s in
            s.dayPart = LocalTime(hour: max(evening.hour - 1, 12), minute: evening.minute)
            return true
        }
    }

    static let russianExtras = Extras(
        lunch: "(в обед|во время обеда)",
        afterWork: "после работы",
        towardEvening: "(ближе к вечеру|под вечер|к вечеру|к концу дня|ближе к концу дня)",
        weekend: "(на выходных|в выходные)",
        everyWeekend: "(каждые выходные|по выходным)",
        monthEnd: "(в конце месяца|в последний день месяца)",
        everyMonthEnd: "(в конце каждого месяца|в последний день каждого месяца|каждый последний день месяца)",
        everyOtherDay: "(через день|каждый второй день)",
        everyOtherWeekday: "(?:каждый второй|каждую вторую|каждое второе) \(PhraseParser.weekdayPattern)",
        nthWeekday: "(?:каждый |каждую |каждое |в |во )?(перв\\w*|втор\\w*|трет\\w*|четверт\\w*|последн\\w*) \(PhraseParser.weekdayPattern) (?:каждого )?месяца",
        ordinals: [("перв", 1), ("втор", 2), ("трет", 3), ("четверт", 4), ("последн", -1)]
    )

    static let englishExtras = Extras(
        lunch: "(at lunch(?:time)?|during lunch)",
        afterWork: "after work",
        towardEvening: "(?:(?:towards?|closer to|by) (?:the )?evening|late (?:in the )?afternoon|(?:by |at )?the end of the day)",
        weekend: "(?:on |at |this |over )?(?:the )?weekend",
        everyWeekend: "(every weekend|on weekends)",
        monthEnd: "(at the end of the month|(?:on )?the last day of the month|end of the month)",
        everyMonthEnd: "(at the end of (?:every|each) month|(?:on )?the last day of (?:every|each) month)",
        everyOtherDay: "every (?:other|second) day",
        everyOtherWeekday: "every (?:other|second) \(PhraseParser.englishWeekdays)",
        nthWeekday: "(?:every |on )?(?:the )?(first|1st|second|2nd|third|3rd|fourth|4th|last) \(PhraseParser.englishWeekdays) of (?:every|each|the) month",
        ordinals: [("first", 1), ("1st", 1), ("second", 2), ("2nd", 2), ("third", 3), ("3rd", 3), ("fourth", 4), ("4th", 4), ("last", -1)]
    )

    static let ukrainianExtras = Extras(
        lunch: "(в обід|у обід|на обід|під час обіду)",
        afterWork: "після роботи",
        towardEvening: "(ближче до вечора|під вечір|надвечір|до вечора|ближче до кінця дня)",
        weekend: "(на вихідних|у вихідні|в вихідні)",
        everyWeekend: "(щовихідних|кожні вихідні|по вихідних)",
        monthEnd: "(в кінці місяця|у кінці місяця|наприкінці місяця|в останній день місяця|у останній день місяця)",
        everyMonthEnd: "(в кінці кожного місяця|наприкінці кожного місяця|в останній день кожного місяця|у останній день кожного місяця)",
        everyOtherDay: "(через день|кожен другий день|щодругого дня)",
        everyOtherWeekday: "(?:кожен другий|кожну другу|кожного другого|щодругого|щодругої|щодругу) \(PhraseParser.ukWeekdays)",
        nthWeekday: "(?:кожен |кожну |кожного |в |у )?(перш\\w*|друг\\w*|трет\\w*|четверт\\w*|останн\\w*) \(PhraseParser.ukWeekdays) (?:кожного )?місяця",
        ordinals: [("перш", 1), ("друг", 2), ("трет", 3), ("четверт", 4), ("останн", -1)]
    )

    static let uzbekExtras = Extras(
        lunch: "(tushlikda|tushlik vaqtida|tushlik paytida)",
        afterWork: "(ishdan keyin|ishdan so'ng)",
        towardEvening: "(kechga yaqin|kechqurunga yaqin|kech tomon|kunning oxirida)",
        weekend: "(dam olish kunlari(?:da)?|dam olish kuni|hafta oxirida)",
        everyWeekend: "(har dam olish kunlari|har dam olish kuni|har hafta oxirida)",
        monthEnd: "(oy oxirida|oyning oxirida|oyning oxirgi kunida|oyning so'nggi kunida)",
        everyMonthEnd: "(har oy oxirida|har oyning oxirida|har oyning oxirgi kunida|har oyning so'nggi kunida)",
        everyOtherDay: "(kunora|kun ora|har ikki kunda)",
        everyOtherWeekday: "har ikkinchi \(PhraseParser.uzWeekdays)",
        nthWeekday: "(?:har )?oyning (birinchi|ikkinchi|uchinchi|to'rtinchi|oxirgi|so'nggi) \(PhraseParser.uzWeekdays)(?:si|sida|sini)?",
        ordinals: [("birinchi", 1), ("ikkinchi", 2), ("uchinchi", 3), ("to'rtinchi", 4), ("oxirgi", -1), ("so'nggi", -1)]
    )

    static let arabicExtras = Extras(
        lunch: "(وقت الغداء|عند الغداء|في الغداء)",
        afterWork: "(بعد العمل|بعد الدوام)",
        towardEvening: "(?:في )?(?:قرب المساء|قبيل المساء|اخر النهار|نهاية اليوم)",
        weekend: "(?:في )?(?:عطلة )?نهاية الاسبوع",
        everyWeekend: "كل (?:عطلة )?نهاية (?:ال)?اسبوع",
        monthEnd: "(?:في )?(نهاية الشهر|اخر يوم من الشهر|اخر يوم في الشهر)",
        everyMonthEnd: "(?:في )?(نهاية كل شهر|اخر يوم من كل شهر|اخر يوم في كل شهر)",
        everyOtherDay: "(كل يومين|يوم بعد يوم|يوما بعد يوم)",
        everyOtherWeekday: "كل اسبوعين (?:في )?\(PhraseParser.arWeekday)",
        nthWeekday: "(?:في )?(?:ال)?(اول|ثاني|ثالث|رابع|اخر) \(PhraseParser.arWeekday) (?:من|في) (?:كل )?(?:ال)?شهر",
        ordinals: [("اول", 1), ("ثاني", 2), ("ثالث", 3), ("رابع", 4), ("اخر", -1)]
    )

    static let frenchExtras = Extras(
        lunch: "(à l'heure du déjeuner|a l'heure du dejeuner|au déjeuner|au dejeuner|pendant la pause déjeuner)",
        afterWork: "(après le travail|apres le travail|après le boulot|apres le boulot)",
        towardEvening: "(en fin de journée|en fin de journee|en fin d'après-midi|en fin d'apres-midi|vers le soir|sur le soir)",
        weekend: "(ce week-end|ce weekend|le week-end|le weekend|pendant le week-end)",
        everyWeekend: "(tous les week-ends|tous les weekends|chaque week-end|chaque weekend)",
        monthEnd: "(à la fin du mois|a la fin du mois|en fin de mois|le dernier jour du mois)",
        everyMonthEnd: "(à la fin de chaque mois|a la fin de chaque mois|le dernier jour de chaque mois|chaque fin de mois)",
        everyOtherDay: "(tous les deux jours|un jour sur deux)",
        everyOtherWeekday: "(?:un \(PhraseParser.frWeekdays) sur deux|tous les deux \(PhraseParser.frWeekdays))",
        nthWeekday: "(?:le |chaque )?(premier|deuxième|deuxieme|second|troisième|troisieme|quatrième|quatrieme|dernier) \(PhraseParser.frWeekdays) (?:du|de chaque) mois",
        ordinals: [("premier", 1), ("deuxi", 2), ("second", 2), ("troisi", 3), ("quatri", 4), ("dernier", -1)]
    )

    static let germanExtras = Extras(
        lunch: "(zum mittagessen|beim mittagessen|in der mittagspause)",
        afterWork: "nach der arbeit",
        towardEvening: "(gegen abend|am späten nachmittag|später am nachmittag|zum abend hin|bis zum abend)",
        weekend: "(am wochenende|übers wochenende|dieses wochenende)",
        everyWeekend: "(jedes wochenende|an wochenenden|wochenends)",
        monthEnd: "(am monatsende|ende des monats|zum monatsende|am letzten tag des monats)",
        everyMonthEnd: "(an jedem monatsende|jedes monatsende|am letzten tag jedes monats|am letzten tag jeden monats)",
        everyOtherDay: "(jeden zweiten tag|alle zwei tage)",
        everyOtherWeekday: "(?:jeden zweiten \(PhraseParser.deWeekdaysFull)|alle zwei wochen (?:am )?\(PhraseParser.deWeekdaysFull))",
        nthWeekday: "(?:jeden |am )?(ersten|zweiten|dritten|vierten|letzten) \(PhraseParser.deWeekdaysFull) (?:im|des|jedes|eines) monats?",
        ordinals: [("erst", 1), ("zweit", 2), ("dritt", 3), ("viert", 4), ("letzt", -1)]
    )
}
