import Foundation
import RemaCore
import UserNotifications
import WidgetKit

enum PushInbox {
    static func handle(_ userInfo: [AnyHashable: Any], content: UNMutableNotificationContent) async {
        guard let push = SharedPush(userInfo: userInfo) else { return }
        // A phone that changed hands gets the pushes of the previous account until Rema signs it up again.
        guard push.recipient == SharedNames.me else {
            content.title = "Rema"
            content.subtitle = ""
            content.body = String(localized: "News in shared reminders", bundle: .app, locale: .app)
            return
        }
        var reminder: Reminder?
        if let item = push.item, let id = UUID(uuidString: item.id) {
            // The store file stays the app's alone; the item waits in the inbox until the app takes it in.
            if (try? SharedInbox.add(item)) != nil {
                WidgetCenter.shared.reloadAllTimelines()
            }
            if let snapshot = SharedInbox.overlaid(SharedStore.load()) {
                reminder = snapshot.reminders.first { $0.id == id }
                // A change of mine still waiting to be sent wins; the alarms stay as the app set them.
                if !SharedLedger.waiting.contains(id) {
                    await reschedule(id, reminder: reminder, settings: snapshot.settings)
                }
            }
            content.userInfo["reminder"] = item.id
        }
        word(push, reminder: reminder, content: content)
    }

    // The app rebuilds every notification when it opens; until then the next alarm of this reminder rings from here.
    private static func reschedule(_ id: UUID, reminder: Reminder?, settings: Settings) async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { Scheduler.reminderID(fromIdentifier: $0) == id }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        guard let reminder, reminder.isLive else { return }
        await QuickNotifications.schedule(reminder, settings: settings, describer: Describer(calendar: .current, locale: .app))
    }

    // The words come in the language of the app and with the name I gave the friend, not the server's.
    private static func word(_ push: SharedPush, reminder: Reminder?, content: UNMutableNotificationContent) {
        let about = push.event == .friend || push.event == .unfriended
        let sent = about ? content.title : content.subtitle
        let friend = SharedNames.name(of: push.actor, fallback: sent)
        if about {
            content.title = friend
            content.subtitle = ""
        } else {
            if let reminder {
                content.title = reminder.title
            }
            content.subtitle = friend
        }
        content.body = body(push.event, reminder: reminder)
    }

    private static func body(_ event: SharedPush.Event, reminder: Reminder?) -> String {
        let now = Date()
        let describer = Describer(calendar: .current, locale: .app)
        let when = reminder?.schedule
            .flatMap { Recurrence.next($0, after: max(now, reminder?.completedThrough ?? now), limit: 1, calendar: .current).first }
            .map { describer.dayAndTime($0, now: now) }
        switch event {
        case .new:
            return when.map { String(localized: "Invitation to a shared reminder, \($0)", bundle: .app, locale: .app) }
                ?? String(localized: "Invitation to a shared reminder", bundle: .app, locale: .app)
        case .changed:
            return when.map { String(localized: "Changed, now \($0)", bundle: .app, locale: .app) }
                ?? String(localized: "Changed", bundle: .app, locale: .app)
        case .deleted:
            return String(localized: "Deleted for everyone", bundle: .app, locale: .app)
        case .accepted:
            return String(localized: "Accepted the invitation", bundle: .app, locale: .app)
        case .declined:
            return String(localized: "Declined the invitation", bundle: .app, locale: .app)
        case .left:
            return String(localized: "No longer in this reminder", bundle: .app, locale: .app)
        case .done:
            return String(localized: "Done, ticked for everybody", bundle: .app, locale: .app)
        case .ticked:
            return String(localized: "Marked as done", bundle: .app, locale: .app)
        case .friend:
            return String(localized: "You are friends in Rema now", bundle: .app, locale: .app)
        case .unfriended:
            return String(localized: "No longer friends in Rema", bundle: .app, locale: .app)
        }
    }
}
