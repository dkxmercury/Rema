import RemaCore
import SwiftUI

struct SnoozeScreen: View {
    let store: Store
    let onBack: () -> Void

    private var chosen: [Int] {
        store.settings.snoozeOptions ?? SnoozeOption.standard
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PanelList {
                        ForEach(Array(SnoozeOption.all.enumerated()), id: \.element) { index, option in
                            if index > 0 {
                                Hairline()
                            }
                            row(option)
                        }
                    }
                    .padding(.top, 14)
                    Text("Up to three. They appear as buttons in the notification.")
                        .font(.app(.golos, 13))
                        .lineHeight(18, .golos, 13)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "Snooze in notifications", leading: .back, action: onBack)
            }
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.small, value: chosen)
    }

    private func row(_ option: Int) -> some View {
        let selected = chosen.contains(option)
        let full = chosen.count >= SnoozeOption.limit && !selected
        return Button {
            toggle(option)
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: Notifier.snoozeTitle(option))
                    .font(.app(.golos, 16, weight: selected ? 600 : 400))
                    .frame(maxWidth: .infinity, alignment: .leading)
                CheckBox(isOn: selected)
            }
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(full)
        .opacity(full ? 0.45 : 1)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggle(_ option: Int) {
        var list = chosen
        if let index = list.firstIndex(of: option) {
            guard list.count > 1 else {
                Feedback.play(.error)
                return
            }
            list.remove(at: index)
        } else {
            guard list.count < SnoozeOption.limit else { return }
            list.append(option)
        }
        let ordered = SnoozeOption.all.filter(list.contains)
        store.update { $0.snoozeOptions = ordered }
        Notifier.shared.configure()
        Feedback.play(.select)
    }
}
