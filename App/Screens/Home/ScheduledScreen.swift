import SwiftUI

struct ScheduledScreen: View {
    let content: ScheduledContent
    var onOpen: (UUID) -> Void = { _ in }
    let onBack: () -> Void
    var loading = false

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if content.isEmpty {
                        Text(loading ? LocalizedStringKey("Loading from your account…") : LocalizedStringKey("Nothing ahead"))
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
                    if !content.monthly.isEmpty {
                        label(Text("Every month"), accent: false, top: content.days.isEmpty ? 14 : 20)
                        PanelList {
                            rows(content.monthly, soonest: false)
                        }
                    }
                    if !content.yearly.isEmpty {
                        label(Text("Every year"), accent: false, top: content.days.isEmpty && content.monthly.isEmpty ? 14 : 20)
                        PanelList {
                            rows(content.yearly, soonest: false)
                        }
                    }
                    if !content.places.isEmpty {
                        label(Text("By place"), accent: false, top: content.days.isEmpty && content.monthly.isEmpty && content.yearly.isEmpty ? 14 : 20)
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
            if let lead = item.lead, let month = item.month {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: lead)
                        .font(.app(.jost, 18, weight: 500))
                        .monospacedDigit()
                    Text(verbatim: month)
                        .font(.app(.golos, 11, weight: 600))
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(Palette.secondary)
                }
                .frame(width: 50, alignment: .leading)
            } else if let lead = item.lead {
                Text(verbatim: lead)
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
