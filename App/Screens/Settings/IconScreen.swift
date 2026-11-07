import SwiftUI

struct IconScreen: View {
    let onBack: () -> Void

    @State private var icons = AppIcons.shared
    @State private var changing = false

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(AppIconChoice.allCases) { choice in
                            card(choice)
                        }
                    }
                    .padding(.top, 18)
                    Text("The icon changes right away, iOS will show a short message about it. Each one has a dark and a tinted look")
                        .font(.app(.golos, 13))
                        .lineHeight(18, .golos, 13)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.top, 16)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "Icon", leading: .back, action: onBack)
            }
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.small, value: icons.current)
    }

    private func card(_ choice: AppIconChoice) -> some View {
        let chosen = icons.current == choice
        let shape = RoundedRectangle(cornerRadius: 22, style: .circular)
        return Button {
            pick(choice)
        } label: {
            VStack(spacing: 10) {
                AppIconTile(choice: choice, size: 72)
                VStack(spacing: 2) {
                    Text(verbatim: choice.name)
                        .font(.app(.golos, 16, weight: 600))
                    Text(verbatim: choice.note)
                        .font(.app(.golos, 12))
                        .foregroundStyle(Palette.secondary)
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .top)
            .panel()
            .overlay {
                if chosen {
                    shape.strokeBorder(Palette.accent, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if chosen {
                    Glyph(paths: Icons.check, size: 14, lineWidth: 3, color: Palette.onAccent)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Palette.accent))
                        .insetShadow(Circle(), .black.opacity(0.14), y: -2)
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .disabled(changing)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func pick(_ choice: AppIconChoice) {
        guard choice != icons.current, !changing else { return }
        changing = true
        Feedback.play(.select)
        Task {
            let done = await icons.choose(choice)
            if !done {
                Feedback.play(.error)
            }
            changing = false
        }
    }
}
