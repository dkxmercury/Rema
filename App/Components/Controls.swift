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

struct RadioMark: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.well)
                .insetShadow(Circle(), Palette.wellShadow, blur: 2, y: 1)
                .overlay(Circle().strokeBorder(Palette.wellBorder, lineWidth: 1))
                .opacity(isOn ? 0 : 1)
            Circle()
                .fill(Palette.accent)
                .insetShadow(Circle(), .black.opacity(0.14), y: -2)
                .scaleEffect(isOn ? 1 : 0.6)
                .opacity(isOn ? 1 : 0)
            Circle()
                .fill(Palette.onAccent)
                .frame(width: 8, height: 8)
                .scaleEffect(isOn ? 1 : 0.2)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: 24, height: 24)
        .animation(Motion.small, value: isOn)
    }
}

struct LeverToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        let track = RoundedRectangle(cornerRadius: 9, style: .circular)
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                track
                    .fill(isOn ? Palette.accent : Palette.track)
                    .insetShadow(track, .black.opacity(0.2), blur: 3, y: 1)
                RoundedRectangle(cornerRadius: 6, style: .circular)
                    .fill(
                        LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xE9E6E0)], startPoint: .top, endPoint: .bottom)
                            .shadow(.drop(color: .black.opacity(0.3), radius: 1.5, x: 0, y: 1))
                    )
                    .frame(width: 24, height: 24)
                    .padding(3)
            }
            .frame(width: 52, height: 30)
            .frame(height: 44)
            .animation(Motion.small, value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(Text(isOn ? LocalizedStringKey("On") : LocalizedStringKey("Off")))
    }
}

struct Segmented<Value: Hashable>: View {
    let options: [(Value, LocalizedStringKey)]
    @Binding var selection: Value
    var fontSize: CGFloat = 15
    @Namespace private var pill

    var body: some View {
        let well = RoundedRectangle(cornerRadius: 14, style: .circular)
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.0 == selection
                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .font(.app(.golos, fontSize, weight: selected ? 600 : 500))
                        .foregroundStyle(selected ? Palette.onSegment : Palette.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 10, style: .circular)
                                    .fill(Palette.segment.shadow(.drop(color: Palette.segmentShadow, radius: 3, x: 0, y: 2)))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background {
            well
                .fill(Palette.panel)
                .insetShadow(well, Palette.segmentWell, blur: 3, y: 1)
        }
        .animation(Motion.small, value: selection)
        .onChange(of: selection) { _, _ in Feedback.play(.select) }
    }
}

struct WellField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var secure = false
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            Group {
                if secure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
            .font(.app(.golos, 17))
            .tint(Palette.accent)
            .focused($focused)
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background {
                shape
                    .fill(Palette.well)
                    .insetShadow(shape, Palette.wellShadow, blur: 2, y: 1)
            }
            .overlay {
                shape.strokeBorder(focused ? Palette.accent : Palette.wellBorder, lineWidth: focused ? 2 : 1)
            }
            .animation(Motion.small, value: focused)
        }
    }
}
