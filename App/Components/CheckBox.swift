import SwiftUI

struct CheckBox: View {
    let isOn: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .circular)
        ZStack {
            if isOn {
                shape
                    .fill(Palette.accent)
                    .insetShadow(shape, .black.opacity(0.14), y: -2)
                Glyph(paths: Icons.check, size: 15, lineWidth: 3, color: Palette.onAccent)
            } else {
                shape
                    .fill(Palette.well)
                    .insetShadow(shape, Palette.wellShadow, blur: 2, y: 1)
                    .overlay(shape.strokeBorder(Palette.wellBorder, lineWidth: 1))
            }
        }
        .frame(width: 26, height: 26)
    }
}
