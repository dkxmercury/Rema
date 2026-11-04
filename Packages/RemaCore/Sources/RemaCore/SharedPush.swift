import Foundation

// What a push about a shared reminder carries besides the text: who it is for, who caused it,
// and the reminder itself when it fits, so the phone can update it before Rema is opened.
public struct SharedPush: Sendable {
    public enum Event: String, Sendable {
        case new
        case changed
        case deleted
        case accepted
        case declined
        case left
        case done
        case ticked
        case friend
        case unfriended
        case comment
        case thanks
    }

    public var event: Event
    public var recipient: String
    public var actor: String
    public var item: SharedItem?
    // The shared reminder the push is about, for its buttons, also when the push carries no data of it.
    public var shared: String?

    public init(event: Event, recipient: String, actor: String, item: SharedItem?, shared: String? = nil) {
        self.event = event
        self.recipient = recipient
        self.actor = actor
        self.item = item
        self.shared = shared
    }

    public init?(userInfo: [AnyHashable: Any]) {
        guard let rema = userInfo["rema"] as? [String: Any],
              let event = (rema["event"] as? String).flatMap(Event.init(rawValue:)),
              let recipient = rema["to"] as? String,
              let actor = rema["actor"] as? String else { return nil }
        self.event = event
        self.recipient = recipient
        self.actor = actor
        shared = rema["shared"] as? String
        if let raw = rema["item"], JSONSerialization.isValidJSONObject(raw),
           let data = try? JSONSerialization.data(withJSONObject: raw) {
            item = try? JSONDecoder().decode(SharedItem.self, from: data)
        } else {
            item = nil
        }
    }
}
