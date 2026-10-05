import Foundation

extension PhraseParser {
    private static let germanWords: Set<String> = [
        "morgen", "heute", "übermorgen", "um", "uhr", "jeden", "jede", "jedes", "täglich", "stunden", "stunde", "minuten",
        "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonntag", "erinnere", "mich", "abends",
        "morgens", "nächsten", "wenn", "ich", "vorher", "dringend", "alle", "tage", "werktags", "jährlich", "monatlich", "einer",
    ]
    private static let frenchWords: Set<String> = [
        "demain", "aujourd'hui", "après-demain", "à", "chaque", "tous", "toutes", "dans", "heures", "heure", "lundi", "mardi",
        "mercredi", "jeudi", "vendredi", "samedi", "dimanche", "rappelle-moi", "rappelle", "soir", "matin", "prochain", "quand",
        "je", "avant", "veille", "jours", "semaine", "mois", "ans", "une", "les", "le", "la", "de", "d'appeler",
    ]
    private static let englishWords: Set<String> = [
        "tomorrow", "today", "tonight", "at", "every", "in", "hours", "hour", "minutes", "monday", "tuesday", "wednesday",
        "thursday", "friday", "saturday", "sunday", "remind", "me", "evening", "morning", "next", "when", "before", "the",
        "to", "on", "days", "week", "month", "year", "an", "a",
    ]

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
        if uzbekText.contains("o'") || uzbekText.contains("g'") { uzbek += 2 }
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
