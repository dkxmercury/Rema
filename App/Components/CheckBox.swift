import SwiftUI

struct CheckBox: View {
    let isOn: Bool
    var size: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size >= 26 ? 8 : 6, style: .circular)
        ZStack {
            if isOn {
                shape
                    .fill(Palette.accent)
                    .insetShadow(shape, .black.opacity(0.14), y: -2)
                Glyph(paths: Icons.check, size: size * 15 / 26, lineWidth: 3, color: Palette.onAccent)
            } else {
                shape
                    .fill(Palette.well)
                    .insetShadow(shape, Palette.wellShadow, blur: 2, y: 1)
                    .overlay(shape.strokeBorder(Palette.wellBorder, lineWidth: 1))
            }
        }
        .frame(width: size, height: size)
    }
}
