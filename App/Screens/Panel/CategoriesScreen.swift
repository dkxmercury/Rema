import RemaCore
import SwiftUI

// Renaming right in the field, reordering by the bars, deleting with the minus; the reminders of a deleted one stay.
struct CategoriesScreen: View {
    let store: Store
    let onBack: () -> Void

    @State private var names: [UUID: String] = [:]
    @State private var newName = ""
    @FocusState private var focused: UUID?
    @FocusState private var adding: Bool

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
                                .padding(.horizontal, 10)
                                .frame(height: 40)
                                .background {
                                    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    shape
                                        .fill(Palette.well)
                                        .insetShadow(shape, Palette.wellShadow, blur: 2, y: 1)
                                }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
                            Button {
                                if newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    adding = true
                                } else {
                                    add()
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Palette.yearly)
                                    Glyph(paths: Icons.plus, size: 12, lineWidth: 3, color: .white)
                                }
                                .frame(width: 22, height: 22)
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel(Text("New category"))
                            TextField("New category", text: $newName)
                                .font(.app(.golos, 16))
                                .submitLabel(.done)
                                .focused($adding)
                                .onSubmit(add)
                                .padding(.horizontal, 10)
                                .frame(height: 40)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Palette.tagBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Palette.panel)
                    }
                } footer: {
                    Text("The name changes right in the field, the order by dragging the bars on the right. If you delete a category, its reminders stay, just without a category")
                        .font(.app(.golos, 13))
                        .lineHeight(18, .golos, 13)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
        .foregroundStyle(Palette.text)
        .pinnedHeader {
            ZStack {
                Text("Categories")
                    .font(.app(.jost, 18, weight: 500))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    RoundIconButton(icon: Icons.back, label: "Back", action: close)
                    Spacer(minLength: 8)
                    Button(action: close) {
                        Text("Done")
                            .font(.app(.golos, 16, weight: 600))
                            .foregroundStyle(Palette.accentTextOnBackground)
                            .padding(.horizontal, 4)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }
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

    private func close() {
        for id in Array(names.keys) {
            commit(id)
        }
        add()
        onBack()
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Feedback.play(.save)
        store.update { $0.addCategory(named: name) }
        newName = ""
    }
}
