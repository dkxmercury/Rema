import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationAccess {
    static let shared = NotificationAccess()

    private(set) var denied = false

    func update(_ status: UNAuthorizationStatus) {
        let off = status == .denied
        if off != denied {
            denied = off
        }
    }

    func refresh() async {
        update(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }
}
