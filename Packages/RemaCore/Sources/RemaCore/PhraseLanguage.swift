import Foundation

extension PhraseParser {
    private static let germanWords: Set<String> = [
        "morgen", "heute", "übermorgen", "um", "uhr", "jeden", "jede", "jedes", "täglich", "stunden", "stunde", "minuten",
        "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonntag", "erinnere", "mich", "abends",
        "morgens", "nächsten", "wenn", "ich", "vorher", "dringend", "alle", "tage", "werktags", "jährlich", "monatlich", "einer",
        "wochenende", "arbeit", "zweiten", "monatsende", "mittagessen", "mittagspause", "monats", "halb", "viertel", "dreiviertel",
        "silvester", "neujahr", "weihnachten", "heiligabend", "kaufen", "außer", "arbeitstag", "bis",
    ]
    private static let frenchWords: Set<String> = [
        "demain", "aujourd'hui", "après-demain", "à", "chaque", "tous", "toutes", "dans", "heures", "heure", "lundi", "mardi",
        "mercredi", "jeudi", "vendredi", "samedi", "dimanche", "rappelle-moi", "rappelle", "soir", "matin", "prochain", "quand",
        "je", "avant", "veille", "jours", "semaine", "mois", "ans", "une", "les", "le", "la", "de", "d'appeler",
        "week-end", "déjeuner", "travail", "boulot", "fin", "sur", "deux", "dernier", "demie", "quart", "moins", "midi", "minuit",
    ]
    private static let englishWords: Set<String> = [
        "tomorrow", "today", "tonight", "at", "every", "in", "hours", "hour", "minutes", "monday", "tuesday", "wednesday",
        "thursday", "friday", "saturday", "sunday", "remind", "me", "evening", "morning", "next", "when", "before", "the",
        "to", "on", "days", "week", "month", "year", "an", "a",
        "weekend", "weekends", "lunch", "work", "other", "last", "end", "o'clock", "half", "past", "quarter",
    ]

    private static let translitMarkers: Set<String> = [
        "zavtra", "segodnya", "sevodnya", "poslezavtra", "utrom", "vecherom", "dnem", "nochyu", "nochju", "kazhdyj", "kazhdyi", "kazhdyy",
        "kazhdiy", "kazhduyu", "kazhdoe", "cherez", "chasov", "chasa", "minut", "ponedelnik", "vtornik", "sredu", "chetverg", "pyatnicu",
        "pyatnitsu", "subbotu", "voskresenye", "napomni", "pozvonit", "kupit", "zabrat", "utra", "vechera", "nedelyu",
    ]

    // «zavtra v 9 pozvonit mame» is Russian typed in Latin letters; the Russian rules read it and the title keeps the letters as typed.
    static func transliterated(_ text: String) -> (String, [Int])? {
        let lower = text.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
        guard lower.count == text.count, words.contains(where: { translitMarkers.contains($0) }),
              !words.contains(where: { $0.count >= 3 && $0 != "den" && (englishWords.contains($0) || germanWords.contains($0) || frenchWords.contains($0)) }) else { return nil }
        let pairs: [(String, String)] = [("shch", "щ"), ("sch", "щ"), ("yo", "ё"), ("yu", "ю"), ("ya", "я"), ("zh", "ж"), ("kh", "х"), ("ts", "ц"), ("ch", "ч"), ("sh", "ш")]
        let single: [Character: String] = [
            "a": "а", "b": "б", "c": "ц", "d": "д", "e": "е", "f": "ф", "g": "г", "h": "х", "i": "и", "j": "й", "k": "к", "l": "л", "m": "м",
            "n": "н", "o": "о", "p": "п", "q": "к", "r": "р", "s": "с", "t": "т", "u": "у", "v": "в", "w": "в", "x": "кс", "z": "з", "'": "ь",
        ]
        let characters = Array(lower)
        var output = ""
        var origin: [Int] = []
        var index = 0
        while index < characters.count {
            if let (latin, cyrillic) = pairs.first(where: { index + $0.0.count <= characters.count && String(characters[index..<(index + $0.0.count)]) == $0.0 }) {
                for symbol in cyrillic {
                    output.append(symbol)
                    origin.append(index)
                }
                index += latin.count
                continue
            }
            let character = characters[index]
            // «y» after a vowel is «й», after a consonant «ы», «kazhdyj» is «каждый».
            let mapped = character == "y" ? (output.last.map { "аеёиоуыэюя".contains($0) } == true ? "й" : "ы") : single[character] ?? String(character)
            for symbol in mapped {
                output.append(symbol)
                origin.append(index)
            }
            index += 1
        }
        return (output, origin)
    }

    // «Call Маша tomorrow at 9», a Cyrillic name inside a Latin phrase.
    static func mostlyLatin(_ text: String) -> Bool {
        let words = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
        let cyrillic = words.filter { $0.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) } }.count
        let latin = words.count - cyrillic
        return latin > cyrillic || (latin > 0 && latin == cyrillic && words.contains { englishWords.contains($0.lowercased()) })
    }

    static func latinLanguage(_ text: String, preferred: String?) -> String {
        let lower = text.lowercased().replacingOccurrences(of: "’", with: "'")
        let words = lower.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "-" }).map(String.init)
        var german = words.filter { germanWords.contains($0) }.count
        var french = words.filter { frenchWords.contains($0) }.count
        let english = words.filter { englishWords.contains($0) }.count
        let uzbekText = uzbekLatin(lower).0
        var uzbek = uzbekText.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init).filter { uzbekWords.contains($0) }.count
        if lower.contains(where: { "äöüß".contains($0) }) { german += 2 }
        if lower.contains(where: { "éèêàçœù".contains($0) }) { french += 2 }
        // «Greg's», «don't» and «O'Brien» are English, in Uzbek a small letter follows «o'» and «g'».
        let marked = uzbekLatin(text.replacingOccurrences(of: "’", with: "'")).0.replacingOccurrences(of: "o'clock", with: "", options: .caseInsensitive)
        if marked.range(of: "[oOgG]'(?!(?:s|t|d|m|ll|re|ve)(?![\\p{L}]))[a-z]", options: .regularExpression) != nil { uzbek += 2 }
        let best = max(german, french, english, uzbek)
        if best == 0 {
            let code = preferred.map { String($0.prefix(2)) } ?? "en"
            return ["de", "fr", "uz"].contains(code) ? code : "en"
        }
        let leaders = [("de", german), ("fr", french), ("en", english), ("uz", uzbek)].filter { $0.1 == best }.map(\.0)
        if leaders.count == 1 { return leaders[0] }
        let code = preferred.map { String($0.prefix(2)) } ?? "en"
        return leaders.contains(code) ? code : (leaders.contains("en") ? "en" : leaders[0])
    }
}
