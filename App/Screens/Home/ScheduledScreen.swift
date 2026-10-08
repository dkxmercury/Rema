import SwiftUI

struct ScheduledScreen: View {
    enum Tab: Hashable {
        case upcoming
        case done
    }

    let content: ScheduledContent
    var done: DoneContent = .empty
    var onOpen: (UUID) -> Void = { _ in }
    let onBack: () -> Void
    var loading = false
    @State var tab = Tab.upcoming

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Segmented(options: [(Tab.upcoming, "Upcoming"), (Tab.done, "Completed")], selection: $tab)
                        .padding(.top, 14)
                    switch tab {
                    case .upcoming:
                        upcoming
                    case .done:
                        history
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

    @ViewBuilder
    private var history: some View {
        if done.isEmpty {
            Text("Nothing done yet")
                .font(.app(.golos, 16, weight: 600))
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .panel()
                .padding(.top, 14)
        }
        if !done.streaks.isEmpty {
            label(Text("Streaks"), accent: false, top: 18)
            PanelList {
                ForEach(Array(done.streaks.enumerated()), id: \.element.id) { index, streak in
                    Button {
                        onOpen(streak.id)
                    } label: {
                        streakRow(streak)
                    }
                    .buttonStyle(RowPressStyle())
                    if index < done.streaks.count - 1 {
                        Hairline()
                    }
                }
            }
        }
        ForEach(Array(done.days.enumerated()), id: \.element.id) { index, day in
            label(Text(verbatim: day.title), accent: false, top: index == 0 && done.streaks.isEmpty ? 18 : 20)
            PanelList {
                ForEach(Array(day.rows.enumerated()), id: \.element.id) { position, row in
                    HStack(spacing: 14) {
                        Text(verbatim: row.time)
                            .font(.app(.jost, 18, weight: 500))
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondary)
                            .frame(width: 50, alignment: .leading)
                        Text(verbatim: row.title)
                            .font(.app(.golos, 16))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Glyph(paths: Icons.check, size: 18, lineWidth: 2.2, color: Palette.accent)
                    }
                    .frame(minHeight: 46)
                    if position < day.rows.count - 1 {
                        Hairline()
                    }
                }
            }
        }
    }

    private func streakRow(_ streak: DoneContent.Streak) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: streak.title)
                    .font(.app(.golos, 16, weight: 500))
                    .multilineTextAlignment(.leading)
                Text(verbatim: streak.text)
                    .font(.app(.golos, 12, weight: 600))
                    .foregroundStyle(Palette.accentText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(Array(streak.recent.enumerated()), id: \.offset) { _, kept in
                    RoundedRectangle(cornerRadius: 3, style: .circular)
                        .fill(kept ? Palette.accent : Palette.track)
                        .frame(width: 10, height: 10)
                }
            }
            .accessibilityHidden(true)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var upcoming: some View {
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
                if let id = item.reminderID {
                    onOpen(id)
                }
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
