import RemaCore
import SwiftUI

struct EarlyScreen: View {
    @Binding var draft: Reminder
    var now: Date
    var calendar: Calendar
    var locale: Locale
    let onBack: () -> Void

    private static let standard = [5, 15, 30, 60, 1_440, 10_080]
    private static let extra = [120, 180, 2_880, 4_320, 20_160]

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    Text(verbatim: String(localized: "\(draft.title.isEmpty ? String(localized: "New reminder") : draft.title) · you can pick several"))
                        .font(.app(.golos, 15))
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                    PanelList {
                        ForEach(EarlyScreen.standard, id: \.self) { minutes in
                            row(minutes)
                            Hairline()
                        }
                        customRow
                    }
                    .padding(.top, 12)
                    if let timeline = timeline {
                        timelinePanel(timeline)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "In advance", leading: .back, action: onBack)
            }
            PrimaryBar(action: onBack) {
                Text("Done")
            }
        }
        .foregroundStyle(Palette.text)
    }

    private func row(_ minutes: Int) -> some View {
        let selected = draft.preAlerts.contains(minutes)
        return Button {
            toggle(minutes)
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: describer.leadText(minutes).capitalizedFirst(locale))
                    .font(.app(.golos, 16, weight: selected ? 600 : 400))
                    .frame(maxWidth: .infinity, alignment: .leading)
                CheckBox(isOn: selected)
            }
            .frame(minHeight: 49)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var customRow: some View {
        let custom = draft.preAlerts.filter { !EarlyScreen.standard.contains($0) }.sorted()
        return Menu {
            ForEach(EarlyScreen.extra, id: \.self) { minutes in
                Button {
                    toggle(minutes)
                } label: {
                    if draft.preAlerts.contains(minutes) {
                        Label(describer.leadText(minutes).capitalizedFirst(locale), systemImage: "checkmark")
                    } else {
                        Text(verbatim: describer.leadText(minutes).capitalizedFirst(locale))
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text("Custom time")
                    .font(.app(.golos, 16))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: custom.isEmpty ? String(localized: "none") : custom.map { describer.leadText($0) }.joined(separator: ", "))
                    .font(.app(.golos, 14))
                    .foregroundStyle(Palette.secondary)
                Glyph(paths: Icons.chevron, size: 16, lineWidth: 2, color: Palette.secondary)
            }
            .frame(minHeight: 50)
            .contentShape(Rectangle())
            .foregroundStyle(Palette.text)
        }
    }

    private struct Entry: Hashable {
        let date: Date
        let label: String
        let isMain: Bool
    }

    private var timeline: [Entry]? {
        guard let schedule = draft.schedule,
              let occurrence = Recurrence.next(schedule, after: now, limit: 1, calendar: calendar).first else { return nil }
        var entries = draft.preAlerts.sorted(by: >).map { minutes in
            Entry(date: occurrence.addingTimeInterval(-Double(minutes) * 60), label: describer.leadText(minutes), isMain: false)
        }
        entries.append(Entry(date: occurrence, label: String(localized: "on time"), isMain: true))
        return entries
    }

    private func timelinePanel(_ entries: [Entry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: countTitle(entries.count))
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Palette.timelineLine)
                    .frame(width: 2)
                    .padding(.vertical, 17)
                    .padding(.leading, 5)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries, id: \.self) { entry in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(entry.isMain ? Palette.accent : Palette.panel)
                                if !entry.isMain {
                                    Circle().strokeBorder(Palette.accent, lineWidth: 2)
                                }
                            }
                            .frame(width: 12, height: 12)
                            Text(verbatim: dateTime(entry.date))
                                .font(.app(.jost, 16, weight: entry.isMain ? 600 : 500))
                            Text(verbatim: entry.label)
                                .font(.app(.golos, 13))
                                .foregroundStyle(Palette.secondary)
                        }
                        .frame(minHeight: 34)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .panel()
        .animation(Motion.standard, value: entries)
    }

    private func countTitle(_ count: Int) -> LocalizedStringKey {
        switch count {
        case 1: return "Remind once"
        case 2: return "Remind twice"
        case 3: return "Remind 3 times"
        case 4: return "Remind 4 times"
        case 5: return "Remind 5 times"
        case 6: return "Remind 6 times"
        case 7: return "Remind 7 times"
        default: return "Remind many times"
        }
    }

    private func dateTime(_ date: Date) -> String {
        let day = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.wide))
        return "\(day), \(describer.time(date))"
    }

    private func toggle(_ minutes: Int) {
        withAnimation(Motion.standard) {
            if let index = draft.preAlerts.firstIndex(of: minutes) {
                draft.preAlerts.remove(at: index)
                Feedback.play(.uncheck)
            } else {
                draft.preAlerts.append(minutes)
                Feedback.play(.check)
            }
        }
    }
}
