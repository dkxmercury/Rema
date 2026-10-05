import Foundation
import RemaCore
import WatchConnectivity

final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    @MainActor
    func send(store: Store) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let payload = WatchPayload.make(reminders: store.reminders, now: Date(), calendar: .current)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? session.updateApplicationContext(["payload": data])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in send(store: Store.shared) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in send(store: Store.shared) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    private func handle(_ message: [String: Any]) {
        guard let raw = message["id"] as? String, let id = UUID(uuidString: raw), let action = message["action"] as? String else { return }
        let occurrence = Date(timeIntervalSince1970: message["occurrence"] as? Double ?? Date().timeIntervalSince1970)
        Task { @MainActor in
            let store = Store.shared
            store.reloadIfChanged()
            switch action {
            case "done":
                store.complete(id, through: occurrence)
                await ReminderNotifications.clear(id, occurrence: occurrence)
            case "undo":
                store.reopen(id, before: occurrence)
            case "snooze":
                store.snooze(id, until: Date().addingTimeInterval(600))
                await ReminderNotifications.clear(id, occurrence: occurrence)
            default:
                return
            }
            Notifier.shared.scheduleSoon()
            send(store: store)
        }
    }
}
