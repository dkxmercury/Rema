import RemaCore
import SwiftUI

// The reminders of one category, today with ticks and the days ahead; what is added here goes into it.
struct CategoryScreen: View {
    let store: Store
    let categoryID: UUID
    var now = Date()
    var calendar: Calendar = .current
    var locale: Locale = AppLanguage.current.locale
    let onOpen: (UUID) -> Void
    let onCompose: () -> Void
    let onBack: () -> Void

    private var category: ReminderCategory? {
        store.settings.category(categoryID)
    }

    private var name: String {
        category?.name ?? ""
    }

    var body: some View {
        let reminders = store.reminders.filter { $0.category == categoryID }
        let today = HomeContent.make(reminders: reminders, places: store.places, now: now, calendar: calendar, locale: locale)
        let ahead = ScheduledContent.make(reminders: reminders, places: store.places, now: now, calendar: calendar, locale: locale)
        ZStack(alignment: .bottom) {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if today.rows.isEmpty && ahead.days.isEmpty && ahead.monthly.isEmpty && ahead.yearly.isEmpty && ahead.places.isEmpty {
                        Text("Nothing in this category yet")
                            .font(.app(.golos, 16, weight: 600))
                            .foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .panel()
                            .padding(.top, 14)
                    }
                    if !today.rows.isEmpty {
                        label(Text("Today"), accent: true, top: 14)
                        PanelList {
                            ForEach(Array(today.rows.enumerated()), id: \.element.id) { index, row in
                                AgendaRow(row: row, onToggle: { toggle(row) })
                                    .contentShape(Rectangle())
                                    .onTapGesture { onOpen(row.reminderID) }
                                if index < today.rows.count - 1 {
                                    Hairline()
                                }
                            }
                        }
                    }
                    ForEach(Array(ahead.days.enumerated()), id: \.element.id) { index, day in
                        label(Text(verbatim: day.title), accent: false, top: index == 0 && today.rows.isEmpty ? 14 : 20)
                        PanelList {
                            rows(day.items)
                        }
                    }
                    if !ahead.monthly.isEmpty {
                        label(Text("Every month"), accent: false, top: 20)
                        PanelList {
                            rows(ahead.monthly)
                        }
                    }
                    if !ahead.yearly.isEmpty {
                        label(Text("Every year"), accent: false, top: 20)
                        PanelList {
                            rows(ahead.yearly)
                        }
                    }
                    if !ahead.places.isEmpty {
                        label(Text("By place"), accent: false, top: 20)
                        PanelList {
                            rows(ahead.places)
                        }
                    }
                    Text(verbatim: String(localized: "Reminders added here go to \(name.quoted())", bundle: .app, locale: .app))
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.top, 16)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            composer
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .foregroundStyle(Palette.text)
        .pinnedHeader {
            HStack {
                RoundIconButton(icon: Icons.back, label: "Back", action: onBack)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Circle()
                        .fill(Palette.category(category?.color ?? 0))
                        .frame(width: 10, height: 10)
                    Text(verbatim: name)
                        .font(.app(.jost, 18, weight: 500))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Color.clear
                    .frame(width: 44, height: 44)
            }
        }
    }

    private func label(_ text: Text, accent: Bool, top: CGFloat) -> some View {
        text
            .font(.app(.golos, 12, weight: 600))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(accent ? Palette.accentText : Palette.secondary)
            .padding(.horizontal, 4)
            .padding(.top, top)
            .padding(.bottom, 8)
    }

    private func rows(_ items: [ScheduledContent.Item]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if let id = item.reminderID {
                Button {
                    onOpen(id)
                } label: {
                    ScheduledItemRow(item: item)
                }
                .buttonStyle(RowPressStyle())
            } else {
                ScheduledItemRow(item: item)
            }
            if index < items.count - 1 {
                Hairline()
            }
        }
    }

    private var composer: some View {
        Button(action: onCompose) {
            HStack(spacing: 8) {
                Text(verbatim: String(localized: "New in \(name.quoted())", bundle: .app, locale: .app))
                    .font(.app(.golos, 16))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .circular)
                        .fill(Palette.accent)
                        .insetShadow(RoundedRectangle(cornerRadius: 12, style: .circular), .black.opacity(0.14), y: -3)
                    Glyph(paths: Icons.plus, size: 22, lineWidth: 2.4, color: Palette.onAccent)
                }
                .frame(width: 44, height: 44)
            }
            .padding(.leading, 18)
            .padding(.trailing, 7)
            .frame(height: 58)
            .inputBar()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
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
}
