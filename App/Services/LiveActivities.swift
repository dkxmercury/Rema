import ActivityKit
import Foundation
import RemaCore

@MainActor
enum LiveActivities {
    private static var window: TimeInterval {
        max(5, min(Remote.shared.number(.liveActivityLead), 240)) * 60
    }

    static func refresh(store: Store, now: Date = Date()) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let running = Activity<ReminderActivity>.activities
        guard Remote.shared.isOn(.liveActivity) else {
            end(running)
            return
        }
        let next = Agenda.upcoming(after: now, reminders: store.activeReminders, calendar: .current, limit: 1).first
        guard let next, next.occurrence.timeIntervalSince(now) <= window, let reminder = store.reminder(next.reminderID) else {
            end(running)
            return
        }
        let state = ReminderActivity.ContentState(
            title: reminder.title,
            due: next.occurrence,
            start: next.occurrence.addingTimeInterval(-window),
            urgent: reminder.urgent
        )
        let content = ActivityContent(state: state, staleDate: next.occurrence.addingTimeInterval(15 * 60))
        if let current = running.first(where: { $0.attributes.reminderID == reminder.id.uuidString }) {
            end(running.filter { $0.id != current.id })
            Task { await current.update(content) }
        } else {
            end(running)
            _ = try? Activity.request(attributes: ReminderActivity(reminderID: reminder.id.uuidString), content: content, pushType: nil)
        }
    }

    private static func end(_ activities: [Activity<ReminderActivity>]) {
        guard !activities.isEmpty else { return }
        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
