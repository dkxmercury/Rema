import SwiftUI

struct UndoToast: View {
    let text: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Glyph(paths: Icons.check, size: 18, lineWidth: 2.2, color: Palette.accentOnDark)
            Text(verbatim: text)
                .font(.app(.golos, 15, weight: 500))
                .foregroundStyle(Palette.dialWindowText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.app(.golos, 15, weight: 600))
                    .foregroundStyle(Palette.accentOnDark)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(height: 50)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .circular)
                .fill(Palette.dialWindow.shadow(.drop(color: .black.opacity(0.22), radius: 12, y: 10)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .circular)
                .strokeBorder(Palette.dialWindowBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}
