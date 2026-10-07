import SwiftUI

struct ScheduledScreen: View {
    let content: ScheduledContent
    var onOpen: (UUID) -> Void = { _ in }
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if content.isEmpty {
                        Text("Nothing ahead")
                            .font(.app(.golos, 16, weight: 600))
                            .foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .panel()
                            .padding(.top, 14)
                    }
                    ForEach(Array(content.days.enumerated()), id: \.element.id) { index, day in
                        label(Text(verbatim: day.title), accent: index == 0, top: index == 0 ? 14 : 20)
                        PanelList {
                            rows(day.items, soonest: index == 0)
                        }
                    }
                    if !content.places.isEmpty {
                        label(Text("By place"), accent: false, top: content.days.isEmpty ? 14 : 20)
                        PanelList {
                            rows(content.places, soonest: false)
                        }
                    }
                    if content.hasRepeats {
                        Text("Repeats are shown once, on their nearest day")
                            .font(.app(.golos, 13))
                            .foregroundStyle(Palette.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "Scheduled", leading: .back, action: onBack)
            }
        }
        .foregroundStyle(Palette.text)
    }

    private func label(_ text: Text, accent: Bool, top: CGFloat) -> some View {
        text
            .font(.app(.golos, 12, weight: 600))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(accent ? Palette.accentText : Palette.secondary)
            .padding(.horizontal, 4)
            .padding(.top, top)
            .padding(.bottom, 8)
    }

    private func rows(_ items: [ScheduledContent.Item], soonest: Bool) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            Button {
                onOpen(item.reminderID)
            } label: {
                row(item, highlighted: soonest && index == 0)
            }
            .buttonStyle(RowPressStyle())
            if index < items.count - 1 {
                Hairline()
            }
        }
    }

    private func row(_ item: ScheduledContent.Item, highlighted: Bool) -> some View {
        HStack(spacing: 14) {
            if let time = item.time {
                Text(verbatim: time)
                    .font(.app(.jost, 18, weight: highlighted ? 600 : 500))
                    .monospacedDigit()
                    .foregroundStyle(highlighted ? Palette.accentText : Palette.text)
                    .frame(width: 50, alignment: .leading)
            } else {
                Glyph(paths: Icons.pin, size: 20, lineWidth: 2, color: Palette.secondary)
                    .frame(width: 50, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.title)
                    .font(.app(.golos, 16, weight: highlighted ? 600 : 400))
                    .multilineTextAlignment(.leading)
                if let subtitle = item.subtitle {
                    Text(verbatim: subtitle)
                        .font(.app(.golos, 12))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: item.subtitle == nil ? 46 : 52)
        .contentShape(Rectangle())
    }
}
