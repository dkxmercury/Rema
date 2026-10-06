import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .circular)
        configuration.label
            .font(.app(.golos, 17, weight: 600))
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background {
                shape
                    .fill(Palette.accent.shadow(.drop(color: Palette.accent.opacity(configuration.isPressed ? 0.18 : 0.30), radius: 9, x: 0, y: 8)))
                    .insetShadow(shape, .black.opacity(0.15), y: -3)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

struct RaisedButtonStyle: ButtonStyle {
    var height: CGFloat = 56
    var radius: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        let pressed = configuration.isPressed
        configuration.label
            .font(.app(.golos, 17, weight: 600))
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                shape
                    .fill(
                        LinearGradient(colors: pressed ? [Palette.raisedBottom, Palette.raisedTop] : [Palette.raisedTop, Palette.raisedBottom], startPoint: .top, endPoint: .bottom)
                            .shadow(.drop(color: Palette.raisedShadowNear, radius: pressed ? 0.5 : 1, x: 0, y: pressed ? 0.5 : 1))
                            .shadow(.drop(color: Palette.raisedShadowFar, radius: pressed ? 2 : 5, x: 0, y: pressed ? 1 : 4))
                    )
                    .insetShadow(shape, Palette.raisedHighlight, y: pressed ? 0 : 1)
            }
            .offset(y: pressed ? 1 : 0)
            .animation(Motion.press, value: pressed)
    }
}

struct RaisedChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
        let pressed = configuration.isPressed
        configuration.label
            .font(.app(.golos, 14, weight: 600))
            .foregroundStyle(Palette.text)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background {
                shape
                    .fill(
                        LinearGradient(colors: pressed ? [Palette.raisedBottom, Palette.raisedTop] : [Palette.raisedTop, Palette.raisedBottom], startPoint: .top, endPoint: .bottom)
                            .shadow(.drop(color: Palette.raisedShadowNear, radius: pressed ? 0.5 : 1, x: 0, y: pressed ? 0.5 : 1))
                            .shadow(.drop(color: Palette.raisedShadowFar, radius: pressed ? 2 : 5, x: 0, y: pressed ? 1 : 4))
                    )
                    .insetShadow(shape, Palette.raisedHighlight, y: pressed ? 0 : 1)
            }
            .offset(y: pressed ? 1 : 0)
            .animation(Motion.press, value: pressed)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

struct SmallButtonStyle: ButtonStyle {
    let prominent: Bool
    var height: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .circular)
        configuration.label
            .font(.app(.golos, 14, weight: 600))
            .foregroundStyle(prominent ? Palette.onAccent : Palette.text)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background {
                if prominent {
                    shape
                        .fill(Palette.accent)
                        .insetShadow(shape, .black.opacity(0.14), y: -2)
                } else {
                    shape
                        .fill(
                            LinearGradient(colors: [Palette.raisedTop, Palette.raisedBottom], startPoint: .top, endPoint: .bottom)
                                .shadow(.drop(color: Palette.raisedShadowNear, radius: 1, y: 1))
                                .shadow(.drop(color: Palette.raisedShadowFar, radius: 5, y: 4))
                        )
                        .insetShadow(shape, Palette.raisedHighlight, y: 1)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
