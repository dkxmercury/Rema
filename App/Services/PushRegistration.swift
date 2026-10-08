import Foundation
import UIKit

// The phone's push address goes to the server after sign-in, so friends' changes reach it while Rema is closed.
@MainActor
final class PushRegistration {
    static let shared = PushRegistration()

    private static let tokenKey = "push.token"
    private static let sentKey = "push.sent"
    private static let sentAtKey = "push.sentAt"

    private var token: String? {
        get { UserDefaults.standard.string(forKey: Self.tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.tokenKey) }
    }

    private init() {}

    func start() {
        guard Account.shared.isSignedIn else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func received(_ data: Data) {
        token = data.map { String(format: "%02x", $0) }.joined()
        Task { await send() }
    }

    // Sent again once a day, in case the server dropped the address after a failed push.
    private func send() async {
        guard let token, let session = Account.shared.session else { return }
        // A new sign-in signs the phone up again: the server ties it to the password the session came from.
        let mark = session.userID + ":" + token + ":" + String(Int(session.issued.timeIntervalSince1970))
        let defaults = UserDefaults.standard
        if defaults.string(forKey: Self.sentKey) == mark, let at = defaults.object(forKey: Self.sentAtKey) as? Date, Date().timeIntervalSince(at) < 24 * 3600 {
            return
        }
        struct Body: Encodable {
            let token: String
            let environment: String
        }
        do {
            try await Backend.send("POST", "/api/rema/devices", body: Body(token: token, environment: Self.environment), token: session.token)
            defaults.set(mark, forKey: Self.sentKey)
            defaults.set(Date(), forKey: Self.sentAtKey)
        } catch {}
    }

    // Taken before the session goes, so the next person on this phone does not get the pushes of this account.
    func forget() -> String? {
        UserDefaults.standard.removeObject(forKey: Self.sentKey)
        return token
    }

    private static var environment: String {
        #if DEBUG
        "development"
        #else
        "production"
        #endif
    }
}
