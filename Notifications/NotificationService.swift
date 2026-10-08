import UserNotifications

// Runs for every push before it shows: the shared reminder is updated on this phone and its alarm set,
// even when Rema itself was swiped away.
final class NotificationService: UNNotificationServiceExtension {
    private let lock = NSLock()
    private var deliver: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        lock.withLock {
            deliver = contentHandler
            self.content = content
        }
        let userInfo = request.content.userInfo
        Task {
            await PushInbox.handle(userInfo, content: content)
            finish()
        }
    }

    override func serviceExtensionTimeWillExpire() {
        finish()
    }

    // The system takes exactly one answer, whichever comes first, the work or the deadline.
    private func finish() {
        let answer: (((UNNotificationContent) -> Void)?, UNMutableNotificationContent?) = lock.withLock {
            defer { deliver = nil }
            return (deliver, content)
        }
        if let handler = answer.0, let content = answer.1 {
            handler(content)
        }
    }
}
