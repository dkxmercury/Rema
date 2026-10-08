import Foundation
import RemaCore
import UserNotifications

// The app rebuilds every notification on its next launch; until then this keeps the new reminder from going silent.
enum QuickNotifications {
    static func schedule(_ reminder: Reminder, settings: Settings, describer: Describer) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        // The next time with its repeats and the few times after it, so a phone that stays closed for days still rings.
        let perTime = 1 + reminder.preAlerts.count
        let plan = Scheduler.plan(reminders: [reminder], settings: settings, now: Date(), calendar: .current, capacity: perTime + Scheduler.nagRepeats + 3 * perTime)
        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            let when = describer.dayAndTime(item.occurrence, now: item.fireDate).capitalizedFirst(describer.locale)
            if case .early = item.kind {
                content.body = String(localized: "\(when), reminding in advance", bundle: .app, locale: .app)
            } else {
                content.body = when
            }
            content.sound = .default
            content.categoryIdentifier = item.nag ? "nag" : "reminder"
            content.interruptionLevel = item.urgent ? .timeSensitive : .active
            content.threadIdentifier = item.reminderID.uuidString
            content.userInfo = ["reminder": item.reminderID.uuidString, "occurrence": item.occurrence.timeIntervalSince1970]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        }
    }
}
