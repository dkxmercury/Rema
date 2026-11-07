import RemaCore
import SwiftUI

struct SidePanel: View {
    let store: Store
    var now = Date()
    var calendar: Calendar = .current
    var locale: Locale = AppLanguage.current.locale
    var places = true
    let onCategory: (UUID) -> Void
    let onEditCategories: () -> Void
    let onFriends: () -> Void
    let onPlaces: () -> Void
    let onBirthdays: () -> Void
    let onSettings: () -> Void

    @State private var naming = false
    @State private var newName = ""

    private var categories: [ReminderCategory] {
        store.settings.categories ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Rema")
                        .font(.app(.jost, 28, weight: 500))
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)
                    HStack(alignment: .center) {
                        SectionLabel(text: "Categories")
                        Spacer(minLength: 8)
                        if !categories.isEmpty {
                            Button("Change", action: onEditCategories)
                                .buttonStyle(SmallButtonStyle(prominent: false, height: 36))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    PanelList {
                        ForEach(categories) { category in
                            row(title: Text(verbatim: category.name), value: "\(count(category))", action: { onCategory(category.id) }) {
                                Circle()
                                    .fill(Palette.category(category.color))
                                    .frame(width: 10, height: 10)
                            }
                            Hairline()
                        }
                        Button {
                            newName = ""
                            naming = true
                        } label: {
                            HStack(spacing: 12) {
                                Glyph(paths: Icons.plus, size: 18, lineWidth: 2.4, color: Palette.accentText)
                                    .frame(width: 20)
                                Text("New category")
                                    .font(.app(.golos, 16, weight: 600))
                                    .foregroundStyle(Palette.accentText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .disabled(categories.count >= ReminderCategory.limit)
                    }
                    PanelList {
                        row(title: Text("Friends"), value: "\(SharedService.shared.state.friends.count)", action: onFriends) {
                            Glyph(paths: Icons.people, size: 20, lineWidth: 2, color: Palette.text)
                        }
                        if places {
                            Hairline()
                            row(title: Text("My places"), value: "\(store.activePlaces.count)", action: onPlaces) {
                                Glyph(paths: Icons.pin, size: 20, lineWidth: 2, color: Palette.text)
                            }
                        }
                        Hairline()
                        row(title: Text("Birthdays"), value: nextBirthday, action: onBirthdays) {
                            Glyph(paths: Icons.cake, size: 20, lineWidth: 2, color: Palette.text)
                        }
                    }
                    .padding(.top, 14)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            PanelList {
                row(title: Text("Settings"), value: nil, action: onSettings) {
                    Glyph(paths: Icons.sliders, size: 20, lineWidth: 2, color: Palette.text)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .foregroundStyle(Palette.text)
        .alert("New category", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Add") { add() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row<Lead: View>(title: Text, value: String?, action: @escaping () -> Void, @ViewBuilder lead: () -> Lead) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                lead()
                    .frame(width: 20)
                title
                    .font(.app(.golos, 16, weight: 500))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    Text(verbatim: value)
                        .font(.app(.golos, 14))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    // Only what is still ahead counts, a one-time reminder that is done is not.
    private func count(_ category: ReminderCategory) -> Int {
        store.reminders.filter { $0.isLive && $0.category == category.id && !($0.schedule?.rule == nil && $0.completedThrough != nil) }.count
    }

    private var nextBirthday: String? {
        guard let first = Birthdays.entries(store.reminders, today: LocalDate(now, in: calendar), patterns: BirthdayPatterns.all).first,
              let date = calendar.date(from: DateComponents(year: first.next.year, month: first.next.month, day: first.next.day, hour: 12)) else { return nil }
        let day = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated))
        return "\(first.name.split(separator: " ").first.map(String.init) ?? first.name), \(day)"
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, categories.count < ReminderCategory.limit else { return }
        Feedback.play(.save)
        store.update { $0.addCategory(named: name) }
    }
}
