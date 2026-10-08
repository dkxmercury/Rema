import Foundation

// What the app knows about shared reminders that the push extension and the widgets must respect as well:
// the reminders whose changes are still waiting to be sent, and the tick the server last confirmed for each one.
// Only the app writes it.
public enum SharedLedger {
    private static let waitingKey = "shared.waiting"
    private static let acknowledgedKey = "shared.acknowledged"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedStore.appGroup)
    }

    public static var waiting: Set<UUID> {
        get { Set((defaults?.stringArray(forKey: waitingKey) ?? []).compactMap(UUID.init(uuidString:))) }
        set { defaults?.set(newValue.map(\.uuidString).sorted(), forKey: waitingKey) }
    }

    public static var acknowledged: [String: Int64] {
        get { (defaults?.dictionary(forKey: acknowledgedKey) ?? [:]).compactMapValues { ($0 as? NSNumber)?.int64Value } }
        set { defaults?.set(newValue.mapValues { NSNumber(value: $0) }, forKey: acknowledgedKey) }
    }

    // My tick as the server has it: the common one when one «done» counts for everybody.
    public static func record(_ items: [SharedItem]) {
        guard !items.isEmpty else { return }
        var known = acknowledged
        for item in items {
            if item.gone || item.data == nil {
                known[item.id] = nil
            } else {
                known[item.id] = item.data?.doneMode == .one ? item.doneThrough : item.myDone
            }
        }
        acknowledged = known
    }

    public static func forget(_ id: String) {
        var known = acknowledged
        guard known.removeValue(forKey: id) != nil else { return }
        acknowledged = known
    }

    public static func clear() {
        defaults?.removeObject(forKey: waitingKey)
        defaults?.removeObject(forKey: acknowledgedKey)
    }
}
