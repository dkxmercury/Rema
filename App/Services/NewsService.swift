import Foundation
import Observation
import UIKit
import UserNotifications

// News are for everybody and need no account; pushes about them go only to those who said yes.
@MainActor
@Observable
final class NewsService {
    static let shared = NewsService()

    struct Item: Codable, Identifiable, Equatable {
        let id: String
        let title: String
        let body: String
        let link: String?
        let date: Int64

        var day: Date {
            Date(timeIntervalSince1970: Double(date) / 1000)
        }

        // Only a page on the web opens, never a link that would start something else on the phone.
        var url: URL? {
            guard let link, let url = URL(string: link), url.scheme == "https", url.host() != nil else { return nil }
            return url
        }
    }

    private static let itemsKey = "news.items"
    private static let langKey = "news.lang"
    private static let fetchedKey = "news.fetchedAt"
    private static let seenKey = "news.seen"
    private static let pushesKey = "news.pushes"
    private static let askedKey = "news.asked"
    private static let sentKey = "news.sent"
    private static let sentAtKey = "news.sentAt"

    private(set) var items: [Item]
    private(set) var seen: Set<String>
    private(set) var pushes: Bool
    var openRequest: String?

    private init() {
        let defaults = UserDefaults.standard
        items = defaults.data(forKey: Self.itemsKey).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? []
        seen = Set(defaults.stringArray(forKey: Self.seenKey) ?? [])
        pushes = defaults.bool(forKey: Self.pushesKey)
    }

    var unread: Int {
        items.filter { !seen.contains($0.id) }.count
    }

    // Asked once, after the update or after the intro for someone new; whatever the answer, it does not come back.
    var shouldAsk: Bool {
        !pushes && !UserDefaults.standard.bool(forKey: Self.askedKey)
    }

    func item(_ id: String) -> Item? {
        items.first { $0.id == id }
    }

    func refresh(force: Bool = false) async {
        let lang = AppLanguage.current.rawValue
        let defaults = UserDefaults.standard
        if !force, defaults.string(forKey: Self.langKey) == lang, let at = defaults.object(forKey: Self.fetchedKey) as? Date, Date().timeIntervalSince(at) < 3600 {
            return
        }
        struct Answer: Decodable {
            let items: [Item]
        }
        guard let answer = try? await Backend.request("GET", "/api/rema/news?lang=\(lang)", as: Answer.self) else { return }
        items = Array(answer.items.prefix(30))
        defaults.set(try? JSONEncoder().encode(items), forKey: Self.itemsKey)
        defaults.set(lang, forKey: Self.langKey)
        defaults.set(Date(), forKey: Self.fetchedKey)
    }

    func markSeen(_ ids: [String]) {
        let fresh = seen.union(ids)
        guard fresh != seen else { return }
        // Only ids still in the list are kept, so the set does not grow for ever.
        let shown = Set(items.map(\.id))
        seen = fresh.filter { shown.contains($0) }
        UserDefaults.standard.set(Array(seen), forKey: Self.seenKey)
    }

    // Synchronous, so a sheet closing right after the answer does not take it for a dismissal.
    func answer(_ yes: Bool) {
        UserDefaults.standard.set(true, forKey: Self.askedKey)
        if yes {
            Task { await setPushes(true) }
        }
    }

    func setPushes(_ on: Bool) async {
        pushes = on
        UserDefaults.standard.set(on, forKey: Self.pushesKey)
        UserDefaults.standard.set(true, forKey: Self.askedKey)
        if on {
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            UIApplication.shared.registerForRemoteNotifications()
        }
        await send(force: true)
    }

    // The server needs the address again after a change of language or zone, and once a day in case it dropped it.
    func send(force: Bool = false) async {
        guard let token = PushRegistration.shared.currentToken else { return }
        let defaults = UserDefaults.standard
        let lang = AppLanguage.current.rawValue
        let zone = TimeZone.current.identifier
        let mark = "\(pushes):\(token):\(lang):\(zone)"
        let previous = defaults.string(forKey: Self.sentKey)
        // A phone that never said yes, or already said no, has nothing on the server to remove.
        if !pushes, previous == nil || previous?.hasPrefix("false:") == true {
            return
        }
        if !force, previous == mark, let at = defaults.object(forKey: Self.sentAtKey) as? Date, Date().timeIntervalSince(at) < 24 * 3600 {
            return
        }
        struct Body: Encodable {
            let token: String
            let environment: String
            let lang: String
            let zone: String
            let on: Bool
        }
        do {
            try await Backend.send("POST", "/api/rema/news/devices", body: Body(token: token, environment: PushRegistration.environment, lang: lang, zone: zone, on: pushes))
            defaults.set(mark, forKey: Self.sentKey)
            defaults.set(Date(), forKey: Self.sentAtKey)
        } catch {}
    }
}
