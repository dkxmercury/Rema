import SwiftUI

struct AgendaRow: View {
    let row: HomeContent.Row
    var minHeight: CGFloat?
    var showsSubtitle = true
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(verbatim: row.time)
                .font(.app(.jost, 18, weight: row.highlighted ? 600 : 500))
                .monospacedDigit()
                .foregroundStyle(timeColor)
                .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title)
                    .font(.app(.golos, 16, weight: row.highlighted ? 600 : 400))
                    .strikethrough(row.done)
                    .foregroundStyle(row.done ? Palette.secondary : Palette.text)
                if showsSubtitle, let subtitle = row.subtitle {
                    Text(verbatim: subtitle)
                        .font(.app(.golos, 12))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onToggle) {
                CheckBox(isOn: row.done)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(.trailing, -9)
            .accessibilityLabel(Text(row.done ? LocalizedStringKey("Mark as not done") : LocalizedStringKey("Mark as done")))
        }
        .frame(minHeight: minHeight ?? (row.subtitle == nil || !showsSubtitle ? 46 : 52))
    }

    private var timeColor: Color {
        if row.done { return Palette.secondary }
        if row.highlighted { return Palette.accentText }
        return Palette.text
    }
}
