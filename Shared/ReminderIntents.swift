import ActivityKit
import AppIntents
import Foundation
import RemaCore
import UserNotifications
import WidgetKit

enum ReminderNotifications {
    static func clear(_ id: UUID, occurrence: Date) async {
        let center = UNUserNotificationCenter.current()
        let prefix = "\(id.uuidString).\(Int(occurrence.timeIntervalSince1970))."
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    static func endActivities(for id: UUID) async {
        for activity in Activity<ReminderActivity>.activities where activity.attributes.reminderID == id.uuidString {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

struct ToggleReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark reminder"
    static let isDiscoverable = false

    @Parameter(title: "Reminder")
    var reminderID: String

    @Parameter(title: "Occurrence")
    var occurrence: Double

    @Parameter(title: "Done")
    var done: Bool

    init() {}

    init(reminderID: UUID, occurrence: Date, done: Bool) {
        self.reminderID = reminderID.uuidString
        self.occurrence = occurrence.timeIntervalSince1970
        self.done = done
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: reminderID) else { return .result() }
        let date = Date(timeIntervalSince1970: occurrence)
        _ = SharedStore.setDone(done, reminder: id, occurrence: date)
        if done {
            await ReminderNotifications.clear(id, occurrence: date)
            await ReminderNotifications.endActivities(for: id)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct CompleteActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Done"
    static let isDiscoverable = false

    @Parameter(title: "Reminder")
    var reminderID: String

    @Parameter(title: "Occurrence")
    var occurrence: Double

    init() {}

    init(reminderID: UUID, occurrence: Date) {
        self.reminderID = reminderID.uuidString
        self.occurrence = occurrence.timeIntervalSince1970
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: reminderID) else { return .result() }
        let date = Date(timeIntervalSince1970: occurrence)
        _ = SharedStore.setDone(true, reminder: id, occurrence: date)
        await ReminderNotifications.clear(id, occurrence: date)
        await ReminderNotifications.endActivities(for: id)
        WidgetCenter.shared.reloadAllTimelines()
        #if APP
        await MainActor.run { Store.shared.reloadIfChanged() }
        await Notifier.shared.reschedule()
        #endif
        return .result()
    }
}

struct SnoozeActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "In 10 minutes"
    static let isDiscoverable = false

    @Parameter(title: "Reminder")
    var reminderID: String

    @Parameter(title: "Occurrence")
    var occurrence: Double

    init() {}

    init(reminderID: UUID, occurrence: Date) {
        self.reminderID = reminderID.uuidString
        self.occurrence = occurrence.timeIntervalSince1970
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: reminderID) else { return .result() }
        let date = Date(timeIntervalSince1970: occurrence)
        _ = SharedStore.snooze(reminder: id, until: Date().addingTimeInterval(600))
        await ReminderNotifications.clear(id, occurrence: date)
        await ReminderNotifications.endActivities(for: id)
        WidgetCenter.shared.reloadAllTimelines()
        #if APP
        await MainActor.run { Store.shared.reloadIfChanged() }
        await Notifier.shared.reschedule()
        #endif
        return .result()
    }
}
