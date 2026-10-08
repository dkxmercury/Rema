import Foundation
import Observation

enum Tip: String {
    case friends
    case voice
    case widget
    case place
    case weather
}

@MainActor
@Observable
final class TipCenter {
    static let shared = TipCenter()

    private static let seenKey = "tips.seen"
    private static let lastKey = "tips.last"

    private(set) var seen: Set<String>
    private var last: Date?

    private init() {
        seen = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
        last = UserDefaults.standard.object(forKey: Self.lastKey) as? Date
    }

    // One tip a day at most; each shows once and only when it has something to say.
    func next(store: Store, now: Date = Date()) -> Tip? {
        guard Remote.shared.isOn(.tips) else { return nil }
        if let last, now.timeIntervalSince(last) < 20 * 3600 {
            return nil
        }
        let reminders = store.activeReminders
        // The newest thing Rema can do is told first, once, on the first open after the update too.
        if !seen.contains(Tip.friends.rawValue), Remote.shared.isOn(.sync) {
            return .friends
        }
        if !seen.contains(Tip.voice.rawValue), VoiceRecognizer.available, !reminders.isEmpty {
            return .voice
        }
        if !seen.contains(Tip.widget.rawValue), reminders.count >= 3 {
            return .widget
        }
        if !seen.contains(Tip.place.rawValue), Remote.shared.isOn(.places), reminders.contains(where: { !$0.placeIDs.isEmpty }) {
            return .place
        }
        let weather = WeatherAdvisor.shared
        if !seen.contains(Tip.weather.rawValue), weather.available, !weather.enabled, reminders.count >= 2 {
            return .weather
        }
        return nil
    }

    func dismiss(_ tip: Tip, now: Date = Date()) {
        seen.insert(tip.rawValue)
        last = now
        UserDefaults.standard.set(Array(seen), forKey: Self.seenKey)
        UserDefaults.standard.set(now, forKey: Self.lastKey)
    }
}
