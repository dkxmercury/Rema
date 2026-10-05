import RemaCore
import SwiftUI

struct EditingTarget: Identifiable {
    let id = UUID()
    let reminder: Reminder
    let isNew: Bool
}

struct RootView: View {
    @State private var store = Store.shared
    @State private var editing: EditingTarget?

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            HomeScreen(
                content: HomeContent.make(
                    reminders: store.reminders,
                    places: store.places,
                    now: timeline.date,
                    calendar: .current,
                    locale: .current
                ),
                onToggle: toggle,
                onOpen: open,
                onCompose: compose
            )
        }
        .fullScreenCover(item: $editing) { target in
            EditorScreen(draft: target.reminder, isNew: target.isNew, store: store, onClose: { editing = nil })
        }
    }

    private func toggle(_ row: HomeContent.Row) {
        Feedback.play(row.done ? .uncheck : .check)
        withAnimation(Motion.standard) {
            if row.done {
                store.reopen(row.reminderID, before: row.occurrence)
            } else {
                store.complete(row.reminderID, through: row.occurrence)
            }
        }
    }

    private func open(_ id: UUID) {
        guard let reminder = store.reminder(id) else { return }
        editing = EditingTarget(reminder: reminder, isNew: false)
    }

    private func compose(_ text: String) {
        let calendar = Calendar.current
        let now = Date()
        let soon = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        let minute = calendar.component(.minute, from: soon)
        let rounded = calendar.date(byAdding: .minute, value: (5 - minute % 5) % 5, to: soon) ?? soon
        let parts = calendar.dateComponents([.hour, .minute], from: rounded)
        let draft = Reminder(
            title: text.trimmingCharacters(in: .whitespacesAndNewlines),
            schedule: Schedule(start: LocalDate(rounded, in: calendar), time: LocalTime(hour: parts.hour ?? 9, minute: parts.minute ?? 0)),
            createdAt: now
        )
        editing = EditingTarget(reminder: draft, isNew: true)
    }
}
