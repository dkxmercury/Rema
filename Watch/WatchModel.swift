import Foundation
import Observation
import RemaCore
import WatchConnectivity
import WatchKit

@Observable
final class WatchModel: NSObject, WCSessionDelegate {
    var payload: WatchPayload?

    @ObservationIgnored private let key = "watch.payload"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: key) {
            payload = try? JSONDecoder().decode(WatchPayload.self, from: data)
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func toggle(_ item: WatchItem) {
        guard var current = payload, let index = current.items.firstIndex(where: { $0.id == item.id }) else { return }
        current.items[index].done.toggle()
        payload = current
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: key)
        }
        WKInterfaceDevice.current().play(current.items[index].done ? .success : .click)
        let message: [String: Any] = [
            "action": current.items[index].done ? "done" : "undo",
            "id": item.reminderID.uuidString,
            "occurrence": item.occurrence.timeIntervalSince1970,
        ]
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in
                session.transferUserInfo(message)
            }
        } else {
            session.transferUserInfo(message)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context["payload"] as? Data,
              let decoded = try? JSONDecoder().decode(WatchPayload.self, from: data) else { return }
        DispatchQueue.main.async {
            self.payload = decoded
            UserDefaults.standard.set(data, forKey: self.key)
        }
    }
}
