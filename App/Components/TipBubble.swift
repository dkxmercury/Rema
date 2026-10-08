import SwiftUI

struct TipBubble: View {
    let tip: Tip
    let onAnswer: (Bool) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .circular)
        VStack(alignment: .trailing, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Glyph(paths: icon, size: 16, lineWidth: 2.2, color: Palette.onAccent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(.golos, 15, weight: 600))
                        .foregroundStyle(Palette.dialWindowText)
                    Text(text)
                        .font(.app(.golos, 14))
                        .lineSpacing(2)
                        .foregroundStyle(Palette.dialWindowText.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 4) {
                if tip == .weather || tip == .friends {
                    answer("Not now", accepted: false, color: Palette.dialWindowText.opacity(0.75))
                }
                answer(tip == .weather ? "Turn on" : tip == .friends ? "Show" : "Got it", accepted: true, color: Palette.accentOnDark)
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(shape.fill(Palette.dialWindow.shadow(.drop(color: .black.opacity(0.28), radius: 14, y: 12))))
        .overlay(shape.strokeBorder(Palette.dialWindowBorder, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            if tip == .voice {
                RoundedRectangle(cornerRadius: 2, style: .circular)
                    .fill(Palette.dialWindow)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(45))
                    .offset(x: -22, y: 6)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func answer(_ title: LocalizedStringKey, accepted: Bool, color: Color) -> some View {
        Button {
            onAnswer(accepted)
        } label: {
            Text(title)
                .font(.app(.golos, 15, weight: 600))
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    private var icon: [String] {
        switch tip {
        case .friends: Icons.people
        case .voice: Icons.microphone
        case .widget: Icons.widgets
        case .place: Icons.pin
        case .weather: Icons.sun
        }
    }

    private var title: LocalizedStringKey {
        switch tip {
        case .friends: "Reminders with friends"
        case .voice: "You can use your voice"
        case .widget: "Rema on the Home Screen"
        case .place: "Places work on their own"
        case .weather: "Weather in the morning and evening?"
        }
    }

    private var text: LocalizedStringKey {
        switch tip {
        case .friends: "Share a reminder with a friend, and it comes to both of you at the same moment."
        case .voice: "Hold the plus and talk. Let go when you are done."
        case .widget: "Add a widget and the dial with the next reminder will always be in sight."
        case .place: "A reminder by place comes even when Rema is closed. Just keep location access on."
        case .weather: "Rema will tell you about rain, snow or frost the evening before and in the morning."
        }
    }
}

struct PlusHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .circular)
            .strokeBorder(Palette.accent.opacity(0.55), lineWidth: 2)
            .background(RoundedRectangle(cornerRadius: 24, style: .circular).strokeBorder(Palette.accent.opacity(0.14), lineWidth: 6).padding(-6))
            .frame(width: 58, height: 58)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
