import RemaCore
import SwiftUI

// Renaming right in the field, reordering by the bars, deleting with the minus; the reminders of a deleted one stay.
struct CategoriesScreen: View {
    let store: Store
    let onBack: () -> Void

    @State private var names: [UUID: String] = [:]
    @State private var newName = ""
    @FocusState private var focused: UUID?

    private var categories: [ReminderCategory] {
        store.settings.categories ?? []
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            List {
                Section {
                    ForEach(categories) { category in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Palette.category(category.color))
                                .frame(width: 12, height: 12)
                                .accessibilityHidden(true)
                            TextField("Name", text: name(of: category))
                                .font(.app(.golos, 16))
                                .submitLabel(.done)
                                .focused($focused, equals: category.id)
                                .onSubmit { commit(category.id) }
                        }
                        .frame(minHeight: 44)
                        .listRowBackground(Palette.panel)
                    }
                    .onMove { source, destination in
                        Feedback.play(.select)
                        store.update { $0.moveCategories(from: source, to: destination) }
                    }
                    .onDelete { indexes in
                        let ids = indexes.map { categories[$0].id }
                        Feedback.play(.delete)
                        store.update { settings in
                            for id in ids {
                                settings.removeCategory(id)
                            }
                        }
                    }
                    if categories.count < ReminderCategory.limit {
                        HStack(spacing: 12) {
                            Glyph(paths: Icons.plus, size: 16, lineWidth: 2.4, color: Palette.accentText)
                                .frame(width: 12)
                                .accessibilityHidden(true)
                            TextField("New category", text: $newName)
                                .font(.app(.golos, 16))
                                .submitLabel(.done)
                                .onSubmit(add)
                        }
                        .frame(minHeight: 44)
                        .listRowBackground(Palette.panel)
                    }
                } footer: {
                    Text("The name changes right in the field, the order by dragging the bars on the right. If you delete a category, its reminders stay, just without a category")
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                        .padding(.top, 6)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
        .foregroundStyle(Palette.text)
        .pinnedHeader {
            ScreenHeader(title: "Categories", leading: .back) {
                commitAll()
                onBack()
            }
        }
        .onChange(of: focused) { old, _ in
            if let old {
                commit(old)
            }
        }
    }

    private func name(of category: ReminderCategory) -> Binding<String> {
        Binding(get: { names[category.id] ?? category.name }, set: { names[category.id] = String($0.prefix(ReminderCategory.nameLimit)) })
    }

    private func commit(_ id: UUID) {
        guard let name = names[id] else { return }
        store.update { $0.renameCategory(id, to: name) }
        names[id] = nil
    }

    private func commitAll() {
        for id in Array(names.keys) {
            commit(id)
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Feedback.play(.save)
        store.update { $0.addCategory(named: name) }
        newName = ""
    }
}
