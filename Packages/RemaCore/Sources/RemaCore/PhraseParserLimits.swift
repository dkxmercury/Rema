import Foundation

extension PhraseParser {
    struct Limits {
        var except: String
        var weekend: String
        var untilEnd: String
        var units: [(prefix: String, days: Int)]
        var untilDate: String
        var times: String
        var span: String
        var range: String
        var lastWorkday: String
        var daysBefore: String
        var holidays: [(pattern: String, month: Int, day: Int)]
        var deadline: String
        var tomorrow: [String]
        var afterDay: String
        var everyMonths: String
        var rare: [(pattern: String, rule: RepeatRule)]
        var sun: [(pattern: String, event: SunEvent)]
    }

    private static let countWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3,
        "eine": 1, "einen": 1, "zwei": 2, "drei": 3,
        "un": 1, "une": 1, "deux": 2, "trois": 3,
        "один": 1, "одну": 1, "два": 2, "две": 2, "три": 3,
    ]

    // A repeat gets its edges right after the language has read it and before the dates,
    // so «до 20 декабря» ends the repeat instead of starting the reminder on that day.
    func limits(_ text: String, _ state: inout State, _ phrases: Limits, weekday: (String) -> Weekday?, month: (String) -> Int?) {
        func groups(_ match: NSTextCheckingResult) -> [String] {
            (1..<match.numberOfRanges).compactMap { group(match, $0, text) }
        }

        func number(_ word: String?) -> Int? {
            guard let word else { return nil }
            return Int(word.trimmingCharacters(in: .whitespaces)) ?? Self.countWords[word.trimmingCharacters(in: .whitespaces)]
        }

        // The day and the month stand in either order, «20 декабря» or «December 20».
        func dayAndMonth(_ words: [String]) -> (day: Int, month: Int)? {
            guard let day = words.compactMap({ Int($0) }).first(where: { (1...31).contains($0) }),
                  let found = words.lazy.filter({ Int($0) == nil }).compactMap(month).first else { return nil }
            return (day, found)
        }

        func unitDays(_ word: String) -> Int {
            phrases.units.first { word.hasPrefix($0.prefix) }?.days ?? 1
        }

        for rare in phrases.rare {
            take(rare.pattern, text, &state) { _, s in
                s.rule = rare.rule
                return true
            }
        }
        take(phrases.everyMonths, text, &state) { m, s in
            guard let count = group(m, 1, text).flatMap({ Int($0) }), (2...24).contains(count) else { return false }
            s.rule = .everyMonths(count)
            return true
        }
        take(phrases.lastWorkday, text, &state) { _, s in
            s.rule = .lastWorkday
            return true
        }
        take(phrases.afterDay, text, &state) { m, s in
            guard let unit = group(m, 2, text) else { return false }
            let rest = (3..<m.numberOfRanges).compactMap { group(m, $0, text) }
            guard let day = rest.compactMap({ Int($0) }).first(where: { (1...31).contains($0) }) else { return false }
            let base: LocalDate
            if let found = rest.lazy.filter({ Int($0) == nil }).compactMap(month).first {
                base = nextDate(month: found, day: day, year: nil)
            } else {
                let today = LocalDate(now, in: calendar)
                var candidate = LocalDate(year: today.year, month: today.month, day: min(day, LocalDate.days(in: today.month, year: today.year)))
                if candidate < today {
                    let next = today.month == 12 ? (today.year + 1, 1) : (today.year, today.month + 1)
                    candidate = LocalDate(year: next.0, month: next.1, day: min(day, LocalDate.days(in: next.1, year: next.0)))
                }
                base = candidate
            }
            s.date = base.adding(days: (number(group(m, 1, text)) ?? 1) * unitDays(unit))
            return true
        }
        for sun in phrases.sun {
            take(sun.pattern, text, &state) { _, s in
                s.sun = sun.event
                return true
            }
        }
        take(phrases.daysBefore, text, &state) { m, s in
            let rest = (3..<m.numberOfRanges).compactMap { group(m, $0, text) }
            guard let unit = group(m, 2, text), let target = dayAndMonth(rest) else { return false }
            let count = number(group(m, 1, text)) ?? 1
            s.date = nextDate(month: target.month, day: target.day, year: nil).adding(days: -count * unitDays(unit))
            return true
        }
        for holiday in phrases.holidays {
            take(holiday.pattern, text, &state) { _, s in
                guard s.date == nil else { return false }
                s.date = nextDate(month: holiday.month, day: holiday.day, year: nil)
                if case .yearly = s.rule {
                    s.rule = .yearly(month: holiday.month, day: holiday.day)
                }
                return true
            }
        }
        if state.rule == nil {
            take(phrases.deadline, text, &state) { m, s in
                let words = groups(m)
                if words.contains(where: { word in phrases.tomorrow.contains { word.hasPrefix($0) } }) {
                    s.dayOffset = 1
                } else if let target = dayAndMonth(words) {
                    s.date = nextDate(month: target.month, day: target.day, year: nil)
                } else if let day = words.lazy.compactMap(weekday).first {
                    s.weekdays = [day]
                } else {
                    return false
                }
                s.deadline = true
                return true
            }
        }
        guard state.rule != nil else { return }
        take(phrases.except, text, &state) { m, s in
            guard let list = group(m, 1, text) else { return false }
            let words = list.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
            var dropped = Set(words.compactMap(weekday))
            if list.contains(phrases.weekend) {
                dropped.formUnion([.saturday, .sunday])
            }
            let base: Set<Weekday>
            switch s.rule {
            case .daily: base = Set(Weekday.allCases)
            case .weekdays: base = [.monday, .tuesday, .wednesday, .thursday, .friday]
            case .weekly(let days) where !days.isEmpty: base = Set(days)
            default: return false
            }
            let kept = base.subtracting(dropped).sorted()
            guard !dropped.isEmpty, !kept.isEmpty else { return false }
            s.rule = kept == [.monday, .tuesday, .wednesday, .thursday, .friday] ? .weekdays : .weekly(kept)
            s.weekdays = kept
            return true
        }
        take(phrases.range, text, &state) { m, s in
            let words = groups(m)
            let days = words.compactMap { Int($0) }.filter { (1...31).contains($0) }
            guard days.count >= 2, let found = words.lazy.filter({ Int($0) == nil }).compactMap(month).first, days[0] <= days[1] else { return false }
            let first = nextDate(month: found, day: days[0], year: nil)
            s.date = first
            s.end = .until(LocalDate(year: first.year, month: found, day: min(days[1], LocalDate.days(in: found, year: first.year))))
            return true
        }
        take(phrases.untilEnd, text, &state) { m, s in
            guard let unit = group(m, 1, text) else { return false }
            let today = LocalDate(now, in: calendar)
            switch unitDays(unit) {
            case 7:
                let first = (calendar.firstWeekday + 5) % 7 + 1
                s.end = .until(today.adding(days: 6 - (today.weekday.rawValue - first + 7) % 7))
            case 365:
                s.end = .until(LocalDate(year: today.year, month: 12, day: 31))
            default:
                s.end = .until(LocalDate(year: today.year, month: today.month, day: LocalDate.days(in: today.month, year: today.year)))
            }
            return true
        }
        take(phrases.untilDate, text, &state) { m, s in
            guard let target = dayAndMonth(groups(m)) else { return false }
            s.end = .until(nextDate(month: target.month, day: target.day, year: nil))
            return true
        }
        take(phrases.times, text, &state) { m, s in
            guard let count = groups(m).compactMap({ Int($0) }).first, (1...999).contains(count) else { return false }
            s.end = .count(count)
            return true
        }
        take(phrases.span, text, &state) { m, s in
            guard let unit = group(m, 2, text) else { return false }
            s.span = (number(group(m, 1, text)) ?? 1) * unitDays(unit)
            return true
        }
    }

    static let russianLimits = Limits(
        except: "(?:,? )?кроме ((?:\(russianDay))(?:(?:,? и |, ?)(?:\(russianDay)))*)",
        weekend: "выходн",
        untilEnd: "до конца (месяца|недели|года)",
        units: [("дн", 1), ("день", 1), ("недел", 7), ("месяц", 30), ("год", 365)],
        untilDate: "до (\\d{1,2}) \(monthPattern)",
        times: "(?:(\\d{1,3}) (?:раз|раза|дней|дня|день|недель|недели) подряд|всего (\\d{1,3}) (?:раз|раза))",
        span: "в течение (?:(\\d{1,3}) )?(дн\\w*|недел\\w*|месяц\\w*)",
        range: "с (\\d{1,2}) (?:по|до) (\\d{1,2}) \(monthPattern)",
        lastWorkday: "(?:в |каждый )?последний рабочий день(?: каждого)? месяца",
        daysBefore: "за (?:(\\d{1,2}|один|одну|два|две|три) )?(дн\\w*|день|недел\\w*) до (\\d{1,2}) \(monthPattern)",
        holidays: [("(?:в |на )?канун нового года|(?:перед|накануне) нов\\w* год\\w*", 12, 31), ("(?:на |в |к )?нов\\w* год\\w*", 1, 1), ("(?:в |на |к )?навруз\\w*", 3, 21)],
        deadline: "(?:до|к) (завтра|понедельника|вторника|среды|четверга|пятницы|субботы|воскресенья|понедельнику|вторнику|среде|четвергу|пятнице|субботе|воскресенью|(\\d{1,2}) \(monthPattern))",
        tomorrow: ["завтр"],
        afterDay: "через (?:(\\d{1,2}|один|одну|два|две|три) )?(дн\\w*|день|недел\\w*) после (\\d{1,2})(?:-?го)?(?: \(monthPattern))?",
        everyMonths: "каждые (\\d{1,2}) месяц\\w*",
        rare: [("(?:раз в квартал|ежеквартально|каждый квартал)", .everyMonths(3)), ("(?:раз в пол ?года|каждые пол ?года|раз в полугодие)", .everyMonths(6)), ("по четным (?:числам|дням)", .evenDays), ("по нечетным (?:числам|дням)", .oddDays)],
        sun: [("(?:на|с) закат\\w*|на заходе солнца|когда (?:зайдет|сядет) солнце", .sunset), ("(?:на|с) рассвет\\w*|на восходе(?: солнца)?|когда взойдет солнце", .sunrise)]
    )
    private static let russianDay = "понедельник\\w*|вторник\\w*|сред[аыуе]|четверг\\w*|пятниц\\w*|суббот\\w*|воскресень\\w*|пн|вт|ср|чт|пт|сб|вс|выходн\\w*"

    static let ukrainianLimits = Limits(
        except: "(?:,? )?крім ((?:\(ukrainianDay))(?:(?:,? і |,? та |, ?)(?:\(ukrainianDay)))*)",
        weekend: "вихідн",
        untilEnd: "до кінця (місяця|тижня|року)",
        units: [("дн", 1), ("день", 1), ("тиж", 7), ("місяц", 30), ("рок", 365), ("рік", 365)],
        untilDate: "до (\\d{1,2}) \(ukMonths)",
        times: "(?:(\\d{1,3}) (?:разів|рази|раз|днів|дні|день) поспіль|усього (\\d{1,3}) (?:разів|рази|раз))",
        span: "протягом (?:(\\d{1,3}) )?(дн\\w*|тижн\\w*|місяц\\w*)",
        range: "з (\\d{1,2}) (?:по|до) (\\d{1,2}) \(ukMonths)",
        lastWorkday: "(?:в |у |кожен )?останній робочий день(?: кожного)? місяця",
        daysBefore: "за (?:(\\d{1,2}) )?(дн\\w*|день|тижд\\w*) до (\\d{1,2}) \(ukMonths)",
        holidays: [("(?:на |в |у |до )?нов\\w* р(?:ік|оку|оком)", 1, 1), ("(?:на |в |у )?різдв\\w*", 12, 25), ("(?:на |в |у )?навруз\\w*", 3, 21)],
        deadline: "до (завтра|понеділка|вівторка|середи|четверга|п'ятниці|суботи|неділі|(\\d{1,2}) \(ukMonths))",
        tomorrow: ["завтр"],
        afterDay: "через (?:(\\d{1,2}) )?(дн\\w*|день|тижд\\w*) після (\\d{1,2})(?:-?го)?(?: \(ukMonths))?",
        everyMonths: "кожні (\\d{1,2}) місяц\\w*",
        rare: [("(?:раз на квартал|щокварталу|щоквартально|кожен квартал)", .everyMonths(3)), ("(?:раз на пів ?року|кожні пів ?року)", .everyMonths(6)), ("по парних (?:числах|днях)", .evenDays), ("по непарних (?:числах|днях)", .oddDays)],
        sun: [("на заході сонця|на захід сонця|із заходом сонця", .sunset), ("на світанку|на сході сонця|зі світанком", .sunrise)]
    )
    private static let ukrainianDay = "понеділ\\w*|вівтор\\w*|серед\\w*|четвер\\w*|п'ятниц\\w*|субот\\w*|неділ\\w*|пн|вт|ср|чт|пт|сб|нд|вихідн\\w*"

    static let englishLimits = Limits(
        except: "(?:,? )?(?:except|but not|excluding|apart from) (?:on )?((?:\(englishDay))(?:(?:,? and |,? or |, ?)(?:on )?(?:\(englishDay)))*)",
        weekend: "weekend",
        untilEnd: "(?:until|till|through) (?:the )?end of (?:the |this )?(month|week|year)",
        units: [("day", 1), ("week", 7), ("month", 30), ("year", 365)],
        untilDate: "(?:until|till|through) (?:\(englishMonths) (\\d{1,2})(?:st|nd|rd|th)?|(?:the )?(\\d{1,2})(?:st|nd|rd|th)? (?:of )?\(englishMonths))",
        times: "(?:(\\d{1,3}) (?:times|days|weeks) in a row|(\\d{1,3}) times in total|(?:a )?total of (\\d{1,3}) times)",
        span: "for (?:(\\d{1,3}|a|one|two|three) )?(days?|weeks?|months?)",
        range: "from (?:\(englishMonths) (\\d{1,2})(?:st|nd|rd|th)? (?:to|until|till|through|-) (\\d{1,2})(?:st|nd|rd|th)?|(?:the )?(\\d{1,2})(?:st|nd|rd|th)? (?:to|until|till|through|-) (?:the )?(\\d{1,2})(?:st|nd|rd|th)? (?:of )?\(englishMonths))",
        lastWorkday: "(?:on |every )?(?:the )?last (?:working|business|work) day of (?:the|every|each) month",
        daysBefore: "(?:(\\d{1,2}|a|one|two|three) )?(days?|weeks?) before (?:\(englishMonths) (\\d{1,2})(?:st|nd|rd|th)?|(?:the )?(\\d{1,2})(?:st|nd|rd|th)? (?:of )?\(englishMonths))",
        holidays: [("(?:on )?new year's eve|before (?:the )?new year", 12, 31), ("(?:on |for )?new year(?:'s day|'s)?", 1, 1), ("(?:on )?christmas eve", 12, 24), ("(?:on |for |at )?christmas(?: day)?", 12, 25), ("(?:on |for )?valentine's day", 2, 14), ("(?:on |for |at )?halloween", 10, 31), ("(?:on |for )?navruz", 3, 21)],
        deadline: "(?:by|before|no later than) (tomorrow|(?:this |next )?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|\(englishMonths) (\\d{1,2})(?:st|nd|rd|th)?|(?:the )?(\\d{1,2})(?:st|nd|rd|th)? (?:of )?\(englishMonths))",
        tomorrow: ["tomorrow"],
        afterDay: "(?:(\\d{1,2}|a|one|two|three) )?(days?|weeks?) after (?:\(englishMonths) )?(?:the )?(\\d{1,2})(?:st|nd|rd|th)?(?: (?:of )?\(englishMonths))?",
        everyMonths: "every (\\d{1,2}) months",
        rare: [("(?:every quarter|quarterly|once a quarter|every three months)", .everyMonths(3)), ("(?:every six months|every half year|twice a year|semiannually|semi-annually)", .everyMonths(6)), ("on (?:even|even-numbered) (?:days|dates)", .evenDays), ("on (?:odd|odd-numbered) (?:days|dates)", .oddDays)],
        sun: [("at (?:sunset|dusk)|when the sun (?:sets|goes down)", .sunset), ("at (?:sunrise|dawn)|when the sun (?:rises|comes up)", .sunrise)]
    )
    private static let englishDay = "mondays?|tuesdays?|wednesdays?|thursdays?|fridays?|saturdays?|sundays?|mon|tues?|wed|thu(?:rs?)?|fri|sat|sun|weekends?"

    static let germanLimits = Limits(
        except: "(?:,? )?(?:außer|ausser|ohne) (?:am |an |den )?((?:\(germanDay))(?:(?:,? und |,? oder |, ?)(?:am |an |den )?(?:\(germanDay)))*)",
        weekend: "wochenend",
        untilEnd: "bis (?:zum )?ende (?:des |der |dieses |dieser )?(monats|woche|jahres)",
        units: [("tag", 1), ("woche", 7), ("monat", 30), ("jahr", 365)],
        untilDate: "bis (?:zum )?(\\d{1,2})\\.? \(deMonths)",
        times: "(?:(\\d{1,3}) (?:mal|tage|wochen) (?:in folge|hintereinander)|insgesamt (\\d{1,3}) mal)",
        span: "(?:für|während) (?:(\\d{1,3}|eine|einen|zwei|drei) )?(tag\\w*|woche\\w*|monat\\w*)",
        range: "vom (\\d{1,2})\\.? bis (?:zum )?(\\d{1,2})\\.? \(deMonths)",
        lastWorkday: "(?:am |jeden )?letzten arbeitstag (?:des |im |jedes )?monats?",
        daysBefore: "(?:(\\d{1,2}|einen|eine|zwei|drei) )?(tage?|wochen?) vor dem (\\d{1,2})\\.? \(deMonths)",
        holidays: [("(?:an |zu )?silvester", 12, 31), ("(?:an |zu )?neujahr", 1, 1), ("(?:an |zu )?heiligabend", 12, 24), ("(?:an |zu )?weihnachten", 12, 25), ("(?:am )?valentinstag", 2, 14)],
        deadline: "(?:bis spätestens|spätestens|bis) (?:zum |am )?(morgen|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag|(\\d{1,2})\\.? \(deMonths))",
        tomorrow: ["morgen"],
        afterDay: "(?:(\\d{1,2}|einen|eine|zwei|drei) )?(tage?|wochen?) nach dem (\\d{1,2})\\.?(?: \(deMonths))?",
        everyMonths: "alle (\\d{1,2}) monate",
        rare: [("(?:jedes quartal|vierteljährlich|quartalsweise|alle drei monate)", .everyMonths(3)), ("(?:halbjährlich|alle sechs monate|jedes halbjahr)", .everyMonths(6)), ("an geraden tagen", .evenDays), ("an ungeraden tagen", .oddDays)],
        sun: [("bei sonnenuntergang|zum sonnenuntergang", .sunset), ("bei sonnenaufgang|zum sonnenaufgang|im morgengrauen", .sunrise)]
    )
    private static let germanDay = "montags?|dienstags?|mittwochs?|donnerstags?|freitags?|samstags?|sonntags?|wochenenden?"

    static let frenchLimits = Limits(
        except: "(?:,? )?sauf (?:le |les )?((?:\(frenchDay))(?:(?:,? et (?:le |les )?|, ?(?:le |les )?)(?:\(frenchDay)))*)",
        weekend: "week",
        untilEnd: "jusqu'(?:à|a) la fin (?:du |de la |de l')?(mois|semaine|année|annee|an)",
        units: [("jour", 1), ("semaine", 7), ("mois", 30), ("an", 365)],
        untilDate: "jusqu'(?:au|à|a) (\\d{1,2}) \(frMonths)",
        times: "(?:(\\d{1,3}) (?:fois|jours|semaines) de suite|(\\d{1,3}) fois au total|au total (\\d{1,3}) fois)",
        span: "pendant (?:(\\d{1,3}|un|une|deux|trois) )?(jours?|semaines?|mois)",
        range: "du (\\d{1,2}) au (\\d{1,2}) \(frMonths)",
        lastWorkday: "(?:le |chaque )?dernier jour ouvr(?:é|e) (?:du|de chaque) mois",
        daysBefore: "(?:(\\d{1,2}|un|une|deux|trois) )?(jours?|semaines?) avant le (\\d{1,2}) \(frMonths)",
        holidays: [("(?:le |au )?réveillon(?: du nouvel an)?", 12, 31), ("(?:le |au |pour le )?(?:jour de l'an|nouvel an)", 1, 1), ("(?:à |a |pour )?no(?:ë|e)l", 12, 25), ("(?:à |a |pour )?la saint-valentin", 2, 14)],
        deadline: "(?:d'ici|avant|au plus tard) (?:le |à |a )?(demain|lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche|(\\d{1,2}) \(frMonths))",
        tomorrow: ["demain"],
        afterDay: "(?:(\\d{1,2}|un|une|deux|trois) )?(jours?|semaines?) après le (\\d{1,2})(?: \(frMonths))?",
        everyMonths: "tous les (\\d{1,2}) mois",
        rare: [("(?:chaque trimestre|tous les trimestres|tous les trois mois|trimestriellement)", .everyMonths(3)), ("(?:tous les six mois|chaque semestre|semestriellement)", .everyMonths(6)), ("les jours pairs", .evenDays), ("les jours impairs", .oddDays)],
        sun: [("au coucher du soleil|au crépuscule|au crepuscule", .sunset), ("au lever du soleil|à l'aube|a l'aube", .sunrise)]
    )
    private static let frenchDay = "lundis?|mardis?|mercredis?|jeudis?|vendredis?|samedis?|dimanches?|week-ends?|weekends?"

    static let uzbekLimits = Limits(
        except: "((?:\(uzbekDay))(?:(?:,? va |, ?)(?:\(uzbekDay)))*) tashqari",
        weekend: "dam olish",
        untilEnd: "(oy|hafta|yil) oxirigacha",
        units: [("kun", 1), ("hafta", 7), ("oy", 30), ("yil", 365)],
        untilDate: "(\\d{1,2})[ -]\(uzMonths)gacha",
        times: "(?:(\\d{1,3}) (?:marta|kun) ketma-ket|jami (\\d{1,3}) marta)",
        span: "(?:(\\d{1,3}) )?(kun|hafta|oy) davomida",
        range: "(?!x)x",
        lastWorkday: "(?:har )?oyning oxirgi ish kuni(?:da)?",
        daysBefore: "(?!x)x",
        holidays: [("(?:navro'z|navruz)\\w*", 3, 21), ("yangi yil\\w*", 1, 1)],
        deadline: "(ertagacha|dushanbagacha|seshanbagacha|chorshanbagacha|payshanbagacha|jumagacha|shanbagacha|yakshanbagacha)",
        tomorrow: ["ertaga"],
        afterDay: "(?!x)x",
        everyMonths: "har (\\d{1,2}) oyda",
        rare: [("har chorakda", .everyMonths(3)), ("(?:har yarim yilda|yarim yilda bir)", .everyMonths(6)), ("juft kunlar(?:da|i)", .evenDays), ("toq kunlar(?:da|i)", .oddDays)],
        sun: [("quyosh bot(?:ganda|ishi bilan)|kun botganda", .sunset), ("quyosh chiq(?:qanda|ishi bilan)|tong otganda", .sunrise)]
    )
    private static let uzbekDay = "dushanba\\w*|seshanba\\w*|chorshanba\\w*|payshanba\\w*|juma\\w*|shanba\\w*|yakshanba\\w*|dam olish kunlari\\w*"

    static let arabicLimits = Limits(
        except: "(?:ما عدا|باستثناء) ((?:\(arabicDay))(?:(?: و ?| ?, ?)(?:\(arabicDay)))*)",
        weekend: "نهاية",
        untilEnd: "حتى نهاية (الشهر|الاسبوع|السنة|العام)",
        units: [("يوم", 1), ("ايام", 1), ("الاسبوع", 7), ("اسبوع", 7), ("اسابيع", 7), ("الشهر", 30), ("شهر", 30), ("اشهر", 30), ("السنة", 365), ("العام", 365)],
        untilDate: "حتى (\\d{1,2}) \(arMonths)",
        times: "(\\d{1,3}) (?:مرات|مرة|ايام|يوما|يوم) (?:متتالية|متتالي|على التوالي)",
        span: "لمدة (?:(\\d{1,3}) )?(يوم|ايام|اسبوع|اسابيع|شهر|اشهر)",
        range: "من (\\d{1,2}) (?:الى|حتى) (\\d{1,2}) \(arMonths)",
        lastWorkday: "(?:في )?اخر يوم عمل (?:من|في) (?:كل )?(?:ال)?شهر",
        daysBefore: "(?!x)x",
        holidays: [("(?:في )?راس السنة", 1, 1), ("(?:في )?عيد الحب", 2, 14), ("(?:في )?(?:عيد )?النوروز", 3, 21)],
        deadline: "(?:قبل|حتى) (غد|الغد|غدا|(?:يوم )?(?:ال)?(?:اثنين|ثلاثاء|اربعاء|خميس|جمعة|جمعه|سبت|احد))",
        tomorrow: ["غد", "الغد"],
        afterDay: "(?!x)x",
        everyMonths: "كل (\\d{1,2}) (?:اشهر|شهور)",
        rare: [("(?:كل ربع سنة|كل ثلاثة اشهر|كل ثلاثه اشهر)", .everyMonths(3)), ("(?:كل ستة اشهر|كل سته اشهر|كل نصف سنة)", .everyMonths(6)), ("في الايام الزوجية", .evenDays), ("في الايام الفردية", .oddDays)],
        sun: [("عند الغروب|وقت الغروب|مع الغروب", .sunset), ("عند الشروق|وقت الشروق|مع الشروق", .sunrise)]
    )
    private static let arabicDay = "(?:يوم )?(?:ال)?(?:اثنين|ثلاثاء|اربعاء|خميس|جمعة|جمعه|سبت|احد)|عطلة نهاية الاسبوع|نهاية الاسبوع"
}
