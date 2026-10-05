import SwiftUI

struct CheckBox: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            if isOn {
                RoundedRectangle(cornerRadius: 8, style: .circular)
                    .fill(Palette.accent.shadow(.inner(color: .black.opacity(0.14), radius: 0, x: 0, y: -2)))
                Glyph(paths: Icons.check, size: 15, lineWidth: 3, color: Palette.onAccent)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .circular)
                    .fill(Palette.well.shadow(.inner(color: Palette.wellShadow, radius: 1, x: 0, y: 1)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .circular)
                            .strokeBorder(Palette.wellBorder, lineWidth: 1)
                    }
            }
        }
        .frame(width: 26, height: 26)
    }
}
