import RemaCore
import SwiftUI

struct ChecklistTarget: Identifiable {
    let id: UUID
}

struct ChecklistSheet: View {
    let store: Store
    let reminderID: UUID
    var now: Date = Date()
    var calendar: Calendar = .current
    var locale: Locale = AppLanguage.current.locale
    let onEdit: () -> Void
    let onClose: () -> Void

    @State private var finishing = false

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if let reminder = store.reminder(reminderID), reminder.deletedAt == nil {
                content(reminder)
            }
        }
        .foregroundStyle(Palette.text)
        .onChange(of: store.reminder(reminderID)?.deletedAt != nil) { _, deleted in
            if deleted {
                onClose()
            }
        }
    }

    private func content(_ reminder: Reminder) -> some View {
        let occurrence = Agenda.current(reminder, now: now, calendar: calendar) ?? now
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: reminder.title)
                        .font(.app(.golos, 20, weight: 600))
                        .lineLimit(2)
                    Text(verbatim: subtitle(reminder, occurrence: occurrence))
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onEdit) {
                    Text("Edit")
                        .font(.app(.golos, 15, weight: 600))
                        .foregroundStyle(Palette.accentText)
                        .frame(height: 40)
                }
                .buttonStyle(RowPressStyle())
                RoundIconButton(icon: Icons.close, label: "Close", action: onClose)
                    .frame(width: 40, height: 40)
            }
            .padding(.top, 22)
            progress(reminder)
                .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ChecklistRows(items: reminder.items, removable: false, onToggle: { item in
                        toggle(item, of: reminder, occurrence: occurrence)
                    }, onAdd: { text in
                        withAnimation(Motion.standard) { store.addItem(text, to: reminderID) }
                    })
                    if reminder.doneWhenChecked {
                        Text("When everything is ticked, the reminder marks itself done and persistent repeats stop.")
                            .font(.app(.golos, 13))
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6)
                            .padding(.top, 12)
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            Button {
                finish(reminder, occurrence: occurrence)
            } label: {
                Text(Checklist.isShopping(reminder.title) ? LocalizedStringKey("Everything bought") : LocalizedStringKey("All done"))
            }
            .buttonStyle(RaisedButtonStyle(height: 52))
            .disabled(finishing)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 18)
    }

    private func subtitle(_ reminder: Reminder, occurrence: Date) -> String {
        let ticked = String(localized: "ticked \(reminder.checkedCount) of \(reminder.items.count)", bundle: .app, locale: .app)
        guard reminder.schedule != nil else { return ticked }
        return "\(describer.time(occurrence)) · \(ticked)"
    }

    private func progress(_ reminder: Reminder) -> some View {
        HStack(spacing: 4) {
            ForEach(reminder.items) { item in
                Capsule()
                    .fill(item.done ? Palette.accent : Palette.track)
                    .frame(height: 5)
            }
        }
        .animation(Motion.standard, value: reminder.items)
        .accessibilityHidden(true)
    }

    private func toggle(_ item: ChecklistItem, of reminder: Reminder, occurrence: Date) {
        let last = reminder.doneWhenChecked && !item.done && reminder.items.filter { !$0.done }.count == 1
        withAnimation(Motion.standard) {
            store.toggleItem(item.id, of: reminderID)
        }
        if last {
            close(completing: occurrence, after: 0.6)
        }
    }

    private func finish(_ reminder: Reminder, occurrence: Date) {
        withAnimation(Motion.standard) {
            store.checkAll(reminderID)
        }
        close(completing: occurrence, after: 0.4)
    }

    // A repeating list unticks itself once done, so the sheet goes away first and the reminder is marked after it.
    private func close(completing occurrence: Date, after delay: Double) {
        finishing = true
        Feedback.play(.save)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            onClose()
            store.complete(reminderID, through: occurrence)
        }
    }
}
