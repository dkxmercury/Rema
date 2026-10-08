import Foundation

public enum Checklist {
    private static let shopping = "(?<![\\p{L}])(?:купи|закуп|докуп|продукт|магазин|покупк|купу|buy|shopping|grocer|kauf|einkauf|lebensmittel|achet|achèt|faire les courses|des courses|les courses|épicerie|sotib ol|xarid|bozor|oziq|сотиб ол|харид|бозор|озиқ|شراء|اشتر|تسوق|بقال|مقاضي)"
    private static let verbs = "(?<![\\p{L}])(?:купить|купи|закупить|докупить|купити|buy|kaufen|acheter|achète|sotib olish|sotib ol|сотиб олиш|сотиб ол|اشتري|اشتر|شراء)(?![\\p{L}])"
    private static let commas = "\\s*(?:,|،|;)\\s*"
    private static let conjunctions = "\\s(?:и|і|й|та|and|und|et|va|ва|و)\\s"
    // «Корм для кошки и собаки» is one thing: after «для», «for» or «für» the «и» joins what the item is for.
    private static let prepositions = "(?<![\\p{L}])(?:для|с|со|из|без|от|з|із|for|with|of|für|mit|pour|avec|uchun|учун|مع)(?![\\p{L}])"
    private static let idioms = ["mac and cheese", "half and half", "fish and chips", "salt and pepper", "bread and butter"]
    private static let amount = "\\s+(?:\\d+(?:[.,]\\d+)?\\s?(?:л|мл|кг|г|шт|уп|пач\\p{L}*|бут\\p{L}*|l|ml|kg|g|pcs|pc|lb|lbs|oz|st|stk|dona|ta|دانه)?|[x×]\\s?\\d+)$"

    // The suggestions read every item on each key press, the pattern is compiled once.
    private static let amountPattern = try? NSRegularExpression(pattern: amount, options: [.caseInsensitive])

    // A shopping phrase gets the offer to make a list right away.
    public static func isShopping(_ title: String) -> Bool {
        let text = PhraseParser.arabicNormalized(title.lowercased()).0
        return text.range(of: shopping, options: .regularExpression) != nil
    }

    // «Купить хлеб, молоко и яйца» gives three items, a single thing stays in the title.
    public static func items(in title: String) -> [String] {
        guard let verb = title.range(of: verbs, options: [.regularExpression, .caseInsensitive]) else { return [] }
        for part in [String(title[verb.upperBound...]), String(title[..<verb.lowerBound])] {
            let found = pieces(part)
            if found.count >= 2 {
                return Array(found.prefix(Reminder.maximumItems))
            }
        }
        return []
    }

    // «Молоко 2 л» keeps the amount apart, the row shows it on the right.
    public static func split(_ text: String) -> (name: String, amount: String?) {
        guard let match = amountPattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range, in: text) else { return (text, nil) }
        let name = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return (text, nil) }
        return (name, text[range].trimmingCharacters(in: .whitespaces))
    }

    // What usually goes along with the items already there; with none yet, what goes into lists most often.
    public static func suggestions(for items: [ChecklistItem], in reminders: [Reminder], excluding id: UUID, limit: Int = 5) -> [String] {
        let current = Set(items.map { key($0.text) })
        var weight: [String: Int] = [:]
        var shown: [String: (text: String, at: Date)] = [:]
        for reminder in reminders where reminder.id != id && reminder.deletedAt == nil && !reminder.items.isEmpty {
            let keys = Set(reminder.items.map { key($0.text) })
            let shared = keys.intersection(current).count
            guard current.isEmpty || shared > 0 else { continue }
            for item in reminder.items {
                let name = key(item.text)
                guard !name.isEmpty, !current.contains(name) else { continue }
                weight[name, default: 0] += 1 + shared
                if shown[name].map({ $0.at < reminder.updatedAt }) ?? true {
                    shown[name] = (split(item.text).name, reminder.updatedAt)
                }
            }
        }
        return weight.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .compactMap { shown[$0.key]?.text }
    }

    // The latest list of a reminder with the same title, or of any shopping one, for «like last time».
    public static func previous(for title: String, in reminders: [Reminder], excluding id: UUID) -> [ChecklistItem]? {
        let name = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let buying = isShopping(title)
        let last = reminders
            .filter { $0.id != id && $0.deletedAt == nil && !$0.items.isEmpty && ($0.title.lowercased() == name || (buying && isShopping($0.title))) }
            .max { $0.updatedAt < $1.updatedAt }
        return last.map { $0.items.map { ChecklistItem(text: $0.text) } }
    }

    private static func key(_ text: String) -> String {
        split(text).name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func pieces(_ text: String) -> [String] {
        let segments = text.replacingOccurrences(of: commas, with: "\u{1F}", options: .regularExpression).split(separator: "\u{1F}").map(String.init)
        let parts = segments.flatMap { segment -> [String] in
            let lower = segment.lowercased()
            guard !idioms.contains(where: { lower.contains($0) }), segment.range(of: prepositions, options: [.regularExpression, .caseInsensitive]) == nil else { return [segment] }
            return segment.replacingOccurrences(of: conjunctions, with: "\u{1F}", options: .regularExpression).split(separator: "\u{1F}").map(String.init)
        }
        return parts
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }
}
