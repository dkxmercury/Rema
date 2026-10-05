import SwiftUI

struct LanguageScreen: View {
    var onClose: () -> Void

    @State private var selected = AppLanguage.current
    private let phone = AppLanguage.system

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element) { index, language in
                            if index > 0 {
                                Hairline()
                            }
                            row(language)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                    .panel()
                    .padding(.top, 16)
                    FormNote(text: "The language changes right away. Dates, times and weekdays follow it.")
                        .padding(.top, 12)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "Language", leading: .close, action: onClose)
            }
            PrimaryBar(action: onClose) {
                Text("Done")
            }
        }
        .foregroundStyle(Palette.text)
        .environment(\.locale, selected.locale)
        .environment(\.layoutDirection, selected.layoutDirection)
        .id(selected)
    }

    private func row(_ language: AppLanguage) -> some View {
        Button {
            guard language != selected else { return }
            Feedback.play(.select)
            AppLanguage.choose(language)
            withAnimation(Motion.small) { selected = language }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: language.nativeName)
                        .font(.app(.golos, 16, weight: 600))
                        .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
                    Text(verbatim: language == phone ? String(localized: "as on the phone") : language.localizedName)
                        .font(.app(.golos, 12))
                        .foregroundStyle(Palette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RadioMark(isOn: language == selected)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(language == selected ? .isSelected : [])
    }
}
