import RemaCore
import SwiftUI

struct ChecklistRows: View {
    let items: [ChecklistItem]
    var removable = true
    var addable = true
    var framed = true
    var focusOnAppear = false
    let onToggle: (ChecklistItem) -> Void
    let onAdd: (String) -> Void
    var onRemove: (ChecklistItem) -> Void = { _ in }

    @State private var newItem = ""
    @FocusState private var adding: Bool

    var body: some View {
        if framed {
            list
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .panel()
        } else {
            list
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                row(item)
                Hairline()
            }
            if addable, items.count < Reminder.maximumItems {
                addRow
            }
        }
        .animation(Motion.standard, value: items)
        .onAppear {
            if focusOnAppear {
                adding = true
            }
        }
    }

    private func row(_ item: ChecklistItem) -> some View {
        let parts = Checklist.split(item.text)
        return HStack(spacing: 6) {
            Button {
                Feedback.play(item.done ? .uncheck : .check)
                onToggle(item)
            } label: {
                CheckBox(isOn: item.done)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(.leading, -9)
            .accessibilityLabel(Text(verbatim: parts.name))
            .accessibilityValue(item.done ? Text("Done") : Text(verbatim: ""))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: parts.name)
                    .font(.app(.golos, 16))
                    .foregroundStyle(item.done ? Palette.secondary : Palette.text)
                    .strikethrough(item.done, color: Palette.secondary)
                if let amount = parts.amount {
                    Text(verbatim: amount)
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if removable {
                Button {
                    Feedback.play(.select)
                    onRemove(item)
                } label: {
                    Glyph(paths: Icons.close, size: 14, lineWidth: 2, color: Palette.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressableStyle())
                .padding(.trailing, -12)
                .accessibilityLabel(Text("Remove item"))
            }
        }
        .frame(minHeight: 48)
        .transition(.opacity)
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            Glyph(paths: Icons.plus, size: 18, lineWidth: 2, color: Palette.accentText)
                .frame(width: 26)
            TextField(text: $newItem, prompt: Text("Add item").foregroundColor(Palette.secondary)) {
                Text("Add item")
            }
            .font(.app(.golos, 16))
            .tint(Palette.accent)
            .focused($adding)
            .submitLabel(.next)
            .onSubmit(add)
            .onChange(of: newItem) { _, text in
                if text.count > ChecklistItem.maximumLength {
                    newItem = String(text.prefix(ChecklistItem.maximumLength))
                }
            }
            .frame(height: 44)
        }
        .frame(minHeight: 48)
    }

    // The field stays open after each item, a list is usually typed in one go.
    private func add() {
        let text = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            adding = false
            return
        }
        Feedback.play(.select)
        onAdd(text)
        newItem = ""
        adding = true
    }
}

struct ChecklistSuggestions: View {
    let title: LocalizedStringKey
    let names: [String]
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.app(.golos, 13))
                .foregroundStyle(Palette.secondary)
                .padding(.horizontal, 4)
            FlowLayout(spacing: 8) {
                ForEach(names, id: \.self) { name in
                    Button {
                        Feedback.play(.select)
                        onPick(name)
                    } label: {
                        HStack(spacing: 6) {
                            Glyph(paths: Icons.plus, size: 14, lineWidth: 2.4, color: Palette.accentText)
                            Text(verbatim: name)
                        }
                    }
                    .buttonStyle(RaisedChipStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ChecklistHints {
    // Staples for the first list, before there is any history to learn from.
    static var staples: [String] {
        [
            String(localized: "Bread", bundle: .app, locale: .app),
            String(localized: "Milk", bundle: .app, locale: .app),
            String(localized: "Eggs", bundle: .app, locale: .app),
            String(localized: "Cheese", bundle: .app, locale: .app),
            String(localized: "Water", bundle: .app, locale: .app),
            String(localized: "Coffee", bundle: .app, locale: .app),
        ]
    }

    static func progress(_ reminder: Reminder) -> String {
        String(localized: "\(reminder.checkedCount) of \(reminder.items.count)", bundle: .app, locale: .app)
    }
}
