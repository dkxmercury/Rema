import SwiftUI

struct AgendaRow: View {
    let row: HomeContent.Row
    var minHeight: CGFloat?
    var showsSubtitle = true
    let onToggle: () -> Void
    var onDelete: (() -> Void)?
    var onPostpone: (() -> Void)?

    @State private var drag: CGFloat = 0
    @State private var leaving = false

    var body: some View {
        content
            .offset(x: drag)
            .background(alignment: .trailing) {
                if drag < 0 {
                    ZStack(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: 12, style: .circular)
                            .fill(Palette.urgent)
                        Glyph(paths: Icons.trash, size: 20, lineWidth: 2, color: .white)
                            .padding(.trailing, 14)
                            .opacity(min(1, -drag / 60))
                    }
                    .frame(width: min(-drag, 600))
                    .padding(.vertical, 4)
                }
            }
            .simultaneousGesture(onDelete == nil ? nil : swipe)
    }

    private var actionable: Bool {
        row.missed && onPostpone != nil
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            line
            if actionable {
                HStack(spacing: 8) {
                    Button(action: onToggle) {
                        Text("Did it")
                    }
                    .buttonStyle(SmallButtonStyle(prominent: true, height: 34))
                    Button {
                        onPostpone?()
                    } label: {
                        Text("Move")
                    }
                    .buttonStyle(SmallButtonStyle(prominent: false, height: 34))
                }
                .padding(.leading, 64)
                .transition(.opacity)
            }
        }
        .padding(.vertical, actionable ? 10 : 0)
        .background(Palette.panel.opacity(drag < 0 ? 1 : 0))
        .accessibilityAction(named: Text("Delete")) {
            onDelete?()
        }
    }

    private var line: some View {
        HStack(spacing: 14) {
            Text(verbatim: row.time)
                .font(.app(.jost, 18, weight: row.highlighted || row.missed ? 600 : 500))
                .monospacedDigit()
                .foregroundStyle(timeColor)
                .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title)
                    .font(.app(.golos, 16, weight: row.highlighted || row.missed ? 600 : 400))
                    .foregroundStyle(row.done ? Palette.secondary : Palette.text)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Palette.secondary)
                            .frame(height: 1.2)
                            .scaleEffect(x: row.done ? 1 : 0, anchor: .leading)
                            .animation(.easeOut(duration: 0.28).delay(row.done ? 0.12 : 0), value: row.done)
                    }
                if row.missed {
                    Text("missed")
                        .font(.app(.golos, 12, weight: 600))
                        .foregroundStyle(Palette.urgentText)
                } else if showsSubtitle, let subtitle = row.subtitle {
                    Text(verbatim: subtitle)
                        .font(.app(.golos, 12))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !actionable {
                Button(action: onToggle) {
                    CheckBox(isOn: row.done)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.trailing, -9)
                .accessibilityLabel(Text(row.done ? LocalizedStringKey("Mark as not done") : LocalizedStringKey("Mark as done")))
            }
        }
        .frame(minHeight: actionable ? 0 : minHeight ?? (row.subtitle == nil || !showsSubtitle ? 46 : 52))
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard !leaving, abs(value.translation.width) > abs(value.translation.height) * 1.3 else { return }
                drag = min(0, value.translation.width)
            }
            .onEnded { value in
                guard !leaving else { return }
                if value.translation.width < -120 || value.predictedEndTranslation.width < -240 {
                    leaving = true
                    Feedback.play(.delete)
                    withAnimation(Motion.standard) { drag = -480 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        onDelete?()
                    }
                } else {
                    withAnimation(Motion.standard) { drag = 0 }
                }
            }
    }

    private var timeColor: Color {
        if row.done { return Palette.secondary }
        if row.missed { return Palette.urgentText }
        if row.highlighted { return Palette.accentText }
        return Palette.text
    }
}
