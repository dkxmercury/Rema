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
        case friend
    }

    public var event: Event
    public var recipient: String
    public var actor: String
    public var item: SharedItem?

    public init(event: Event, recipient: String, actor: String, item: SharedItem?) {
        self.event = event
        self.recipient = recipient
        self.actor = actor
        self.item = item
    }

    public init?(userInfo: [AnyHashable: Any]) {
        guard let rema = userInfo["rema"] as? [String: Any],
              let event = (rema["event"] as? String).flatMap(Event.init(rawValue:)),
              let recipient = rema["to"] as? String,
              let actor = rema["actor"] as? String else { return nil }
        self.event = event
        self.recipient = recipient
        self.actor = actor
        if let raw = rema["item"], JSONSerialization.isValidJSONObject(raw),
           let data = try? JSONSerialization.data(withJSONObject: raw) {
            item = try? JSONDecoder().decode(SharedItem.self, from: data)
        } else {
            item = nil
        }
    }
}
