import Foundation
import RemaCore

extension Store {
    // Every screen reads a phrase the same way: with the places, the spot for sunrise and sunset, and the words sent by the server.
    @MainActor
    func phraseParser(now: Date, calendar: Calendar = .current) -> PhraseParser {
        var parser = PhraseParser(now: now, calendar: calendar, morning: settings.morning, evening: settings.evening, places: activePlaces.map(\.name), preferred: AppLanguage.current.rawValue)
        parser.coordinate = WeatherAdvisor.savedCoordinate ?? livePlaces.first.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
        parser.synonyms = Remote.shared.words
        return parser
    }
}

// «Вечером» moved to 20:00 three times in a row: the evening of this person is probably 20:00.
enum PartShift {
    enum Part: String {
        case morning
        case evening
    }

    private static func key(_ part: Part) -> String {
        "partShift.\(part.rawValue)"
    }

    static func record(_ part: Part, _ time: LocalTime) {
        var recent = UserDefaults.standard.array(forKey: key(part)) as? [Int] ?? []
        recent.append(time.hour * 60 + time.minute)
        UserDefaults.standard.set(Array(recent.suffix(5)), forKey: key(part))
    }

    static func reset(_ part: Part) {
        UserDefaults.standard.removeObject(forKey: key(part))
    }

    static func suggestion(_ part: Part, current: LocalTime) -> LocalTime? {
        let recent = UserDefaults.standard.array(forKey: key(part)) as? [Int] ?? []
        guard recent.count >= 3, let last = recent.last, recent.suffix(3).allSatisfy({ $0 == last }), last != current.hour * 60 + current.minute else { return nil }
        return LocalTime(hour: last / 60, minute: last % 60)
    }
}
