import Foundation
import Observation

// The bell: what friends did with you, kept on the server for a month, together with Rema news.
// What is read is kept on this phone, the same for the bell and for the news.
@MainActor
@Observable
final class BellService {
    static let shared = BellService()

    struct Event: Codable, Identifiable, Equatable {
        let id: String
        let kind: String
        let actor: String
        let actorName: String
        let item: String
        let title: String
        let at: Int64

        var day: Date {
            Date(timeIntervalSince1970: Double(at) / 1000)
        }
    }

    enum Row: Identifiable {
        case event(Event)
        case news(NewsService.Item)

        var id: String {
            switch self {
            case .event(let event): "event-" + event.id
            case .news(let item): "news-" + item.id
            }
        }

        var day: Date {
            switch self {
            case .event(let event): event.day
            case .news(let item): item.day
            }
        }
    }

    private static let eventsKey = "bell.events"
    private static let seenKey = "bell.seen"
    private static let fetchedKey = "bell.fetchedAt"

    private(set) var events: [Event]
    private(set) var seen: Set<String>

    private init() {
        let defaults = UserDefaults.standard
        events = defaults.data(forKey: Self.eventsKey).flatMap { try? JSONDecoder().decode([Event].self, from: $0) } ?? []
        seen = Set(defaults.stringArray(forKey: Self.seenKey) ?? [])
    }

    var unread: Int {
        events.filter { !seen.contains($0.id) }.count + NewsService.shared.unread
    }

    var rows: [Row] {
        (events.map(Row.event) + NewsService.shared.items.map(Row.news)).sorted { $0.day > $1.day }
    }

    func isRead(_ row: Row) -> Bool {
        switch row {
        case .event(let event): seen.contains(event.id)
        case .news(let item): NewsService.shared.seen.contains(item.id)
        }
    }

    func refresh(force: Bool = false) async {
        await NewsService.shared.refresh(force: force)
        guard let session = Account.shared.session else { return }
        let defaults = UserDefaults.standard
        if !force, let at = defaults.object(forKey: Self.fetchedKey) as? Date, Date().timeIntervalSince(at) < 60 {
            return
        }
        struct Answer: Decodable {
            let items: [Event]
        }
        guard let answer = try? await Backend.request("GET", "/api/rema/inbox", token: session.token, as: Answer.self),
              Account.shared.session?.userID == session.userID else { return }
        events = answer.items
        // Only ids still in the list are kept, so the set does not grow for ever.
        seen = seen.intersection(events.map(\.id))
        save()
        defaults.set(Date(), forKey: Self.fetchedKey)
    }

    func markRead(_ row: Row) {
        switch row {
        case .event(let event):
            guard !seen.contains(event.id) else { return }
            seen.insert(event.id)
            save()
        case .news(let item):
            NewsService.shared.markSeen([item.id])
        }
    }

    func markAllRead() {
        seen.formUnion(events.map(\.id))
        save()
        NewsService.shared.markSeen(NewsService.shared.items.map(\.id))
    }

    // What friends did belongs to the account; it goes with it.
    func clear() {
        events = []
        seen = []
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.eventsKey)
        defaults.removeObject(forKey: Self.seenKey)
        defaults.removeObject(forKey: Self.fetchedKey)
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(events), forKey: Self.eventsKey)
        defaults.set(Array(seen), forKey: Self.seenKey)
    }
}
