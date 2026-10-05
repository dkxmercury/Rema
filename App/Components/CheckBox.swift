import SwiftUI

struct CheckBox: View {
    let isOn: Bool
    var size: CGFloat = 26
    @State private var settled = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size >= 26 ? 8 : 6, style: .circular)
        ZStack {
            shape
                .fill(Palette.well)
                .insetShadow(shape, Palette.wellShadow, blur: 2, y: 1)
                .overlay(shape.strokeBorder(Palette.wellBorder, lineWidth: 1))
                .opacity(isOn ? 0 : 1)
            if isOn {
                ZStack {
                    shape
                        .fill(Palette.accent)
                        .insetShadow(shape, .black.opacity(0.14), y: -2)
                    CheckMark(animated: settled, size: size * 15 / 26)
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.small, value: isOn)
        .onAppear { settled = true }
    }
}

private struct CheckMark: View {
    let size: CGFloat
    @State private var progress: CGFloat

    init(animated: Bool, size: CGFloat) {
        self.size = size
        _progress = State(initialValue: animated ? 0 : 1)
    }

    var body: some View {
        CheckShape()
            .trim(from: 0, to: progress)
            .stroke(Palette.onAccent, style: StrokeStyle(lineWidth: 3 * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .onAppear {
                guard progress < 1 else { return }
                withAnimation(.easeOut(duration: 0.18).delay(0.06)) { progress = 1 }
            }
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 24
        var path = Path()
        path.move(to: CGPoint(x: 5 * unit, y: 12.5 * unit))
        path.addLine(to: CGPoint(x: 9.5 * unit, y: 17 * unit))
        path.addLine(to: CGPoint(x: 19 * unit, y: 7.5 * unit))
        return path
    }
}
