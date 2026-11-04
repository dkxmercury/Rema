import RemaCore
import SwiftUI

struct PrioritiesSheet: View {
    let store: Store
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let onClose: () -> Void
    @State private var chosen: [UUID]

    init(store: Store, now: Date = Date(), calendar: Calendar = .current, locale: Locale = AppLanguage.current.locale, onClose: @escaping () -> Void) {
        self.store = store
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.onClose = onClose
        _chosen = State(initialValue: store.settings.priorityIDs(on: LocalDate(now, in: calendar)))
    }

    // Each reminder once, by its first time today; a done one stays only while it is picked, so it can be taken off.
    private var rows: [HomeContent.Row] {
        var seen = Set<UUID>()
        return HomeContent.rows(on: now, reminders: store.reminders, places: store.places, now: now, calendar: calendar, locale: locale).filter { row in
            guard !seen.contains(row.reminderID), !row.done || chosen.contains(row.reminderID) else { return false }
            seen.insert(row.reminderID)
            return true
        }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Main things today")
                            .font(.app(.jost, 26, weight: 500))
                        Text("Mark up to three things")
                            .font(.app(.golos, 14))
                            .foregroundStyle(Palette.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(chosen.count) of \(Priorities.limit)")
                        .font(.app(.jost, 14, weight: 500))
                        .foregroundStyle(Palette.onSegment)
                        .contentTransition(.numericText())
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(Palette.segment))
                }
                .padding(.top, 28)
                ScrollView {
                    list
                        .padding(.top, 16)
                    Text("To choose another, unstar one of the three. You can change this at any time.")
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 18)
            PrimaryBar(action: save) {
                Text("Done")
            }
        }
        .foregroundStyle(Palette.text)
    }

    @ViewBuilder
    private var list: some View {
        let today = rows
        if today.isEmpty {
            Text("Nothing for today")
                .font(.app(.golos, 16, weight: 600))
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .panel()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(today.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Hairline()
                    }
                    line(row)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
            .panel()
        }
    }

    private func line(_ row: HomeContent.Row) -> some View {
        let on = chosen.contains(row.reminderID)
        let open = on || chosen.count < Priorities.limit
        return Button {
            toggle(row.reminderID)
        } label: {
            HStack(spacing: 14) {
                Text(verbatim: row.time)
                    .font(.app(.jost, 18, weight: 500))
                    .monospacedDigit()
                    .foregroundStyle(row.done ? Palette.secondary : Palette.text)
                    .timeColumn()
                Text(verbatim: row.title)
                    .font(.app(.golos, 16))
                    .foregroundStyle(row.done ? Palette.secondary : Palette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(paths: Icons.star, size: 24, lineWidth: 1.8, color: on ? Palette.accent : Palette.secondary, filled: on)
                    .frame(width: 44, height: 44)
                    .padding(.trailing, -9)
                    .opacity(open ? 1 : 0.35)
            }
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(!open)
        .accessibilityLabel(Text(on ? LocalizedStringKey("Remove from main: \(row.title)") : LocalizedStringKey("Make it main: \(row.title)")))
    }

    private func toggle(_ id: UUID) {
        Feedback.play(.select)
        withAnimation(Motion.small) {
            if let index = chosen.firstIndex(of: id) {
                chosen.remove(at: index)
            } else if chosen.count < Priorities.limit {
                chosen.append(id)
            }
        }
    }

    private func save() {
        let live = Set(store.activeReminders.map(\.id))
        store.update { $0.priorities = Priorities(day: LocalDate(now, in: calendar), ids: chosen.filter(live.contains)) }
        Feedback.play(.save)
        onClose()
    }
}
