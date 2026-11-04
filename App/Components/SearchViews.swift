import RemaCore
import SwiftUI

struct SearchBar: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    let searching: Bool

    var body: some View {
        HStack(spacing: 10) {
            let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
            HStack(spacing: 8) {
                Glyph(paths: Icons.search, size: 18, lineWidth: 2, color: Palette.secondary)
                TextField(text: $query, prompt: Text("Find a reminder").foregroundColor(Palette.secondary)) {
                    Text("Find a reminder")
                }
                .font(.app(.golos, 15))
                .tint(Palette.accent)
                .focused(focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Glyph(paths: Icons.close, size: 10, lineWidth: 3.4, color: .white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Palette.dialDone))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear"))
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, query.isEmpty ? 12 : 6)
            .frame(height: 44)
            .background {
                shape
                    .fill(Palette.well)
                    .insetShadow(shape, Palette.wellShadow, blur: 3, y: 1)
            }
            .overlay {
                shape.strokeBorder(Palette.wellBorder, lineWidth: 1)
            }
            if searching {
                Button {
                    query = ""
                    focused.wrappedValue = false
                } label: {
                    Text("Cancel")
                        .font(.app(.golos, 16, weight: 600))
                        .foregroundStyle(Palette.accentTextOnBackground)
                        .frame(height: 44)
                        .padding(.horizontal, 2)
                }
                .buttonStyle(RowPressStyle())
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
    }
}

struct SearchResultsList: View {
    static let pageSize = 50

    let query: String
    let store: Store
    let now: Date
    let calendar: Calendar
    let locale: Locale
    @Binding var limit: Int
    let onOpen: (UUID) -> Void

    static func people(_ reminder: Reminder) -> [String] {
        reminder.shared.map(SharedNames.people) ?? []
    }

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    var body: some View {
        let found = ReminderSearch.find(query, in: store.reminders, places: store.places, people: Self.people, now: now, calendar: calendar, locale: locale)
        VStack(alignment: .leading, spacing: 0) {
            if !found.upcoming.isEmpty {
                SectionLabel(text: "Upcoming")
                    .padding(.top, 20)
                list(Array(found.upcoming.prefix(limit)))
                    .padding(.top, 8)
            }
            if !found.earlier.isEmpty {
                SectionLabel(text: found.earlier.allSatisfy(\.done) ? "Completed" : "Earlier")
                    .padding(.top, 18)
                list(Array(found.earlier.prefix(limit)))
                    .padding(.top, 8)
            }
            if found.upcoming.count > limit || found.earlier.count > limit {
                Button {
                    limit += Self.pageSize
                } label: {
                    Text("Show more")
                }
                .buttonStyle(SmallButtonStyle(prominent: false))
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            }
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Group {
                    if found.count == 0 {
                        Text("Nothing found")
                    } else {
                        Text("Found \(found.count) reminders")
                    }
                }
                .font(.app(.golos, 13))
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, found.count == 0 ? 28 : 14)
            }
        }
        .animation(Motion.standard, value: query)
    }

    private func list(_ hits: [SearchHit]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                if index > 0 {
                    Hairline()
                }
                if let reminder = store.reminder(hit.reminderID) {
                    Button {
                        onOpen(hit.reminderID)
                    } label: {
                        row(hit, reminder)
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .panel()
    }

    private func row(_ hit: SearchHit, _ reminder: Reminder) -> some View {
        HStack(spacing: 14) {
            Group {
                if let date = hit.date {
                    Text(verbatim: describer.shortTime(date))
                        .font(.app(.jost, 18, weight: 500))
                        .monospacedDigit()
                } else if !reminder.placeIDs.isEmpty {
                    Glyph(paths: Icons.pin, size: 18, lineWidth: 2, color: Palette.text)
                }
            }
            .foregroundStyle(hit.done ? Palette.secondary : Palette.text)
            .timeColumn()
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.field == .title ? highlighted(reminder.title, done: hit.done) : AttributedString(reminder.title))
                    .font(.app(.golos, 16))
                    .strikethrough(hit.done, color: Palette.secondary)
                    .foregroundStyle(hit.done ? Palette.secondary : Palette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                let line = details(hit, reminder)
                if !line.isEmpty {
                    Text(hit.field == .title ? AttributedString(line) : highlighted(line, done: hit.done))
                        .font(.app(.golos, 12))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Glyph(paths: Icons.chevron, size: 16, lineWidth: 2, color: Palette.secondary)
        }
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    private func details(_ hit: SearchHit, _ reminder: Reminder) -> String {
        switch hit.field {
        case .item(let text):
            return String(localized: "in the list · \(text)", bundle: .app, locale: .app)
        case .place:
            return describer.placeText(reminder, places: store.places)
        case .person:
            let names = reminder.shared.map(SharedNames.line) ?? ""
            return [hit.date.map { describer.relativeDay($0, now: now) }, String(localized: "shared · \(names)", bundle: .app, locale: .app)].compactMap { $0 }.joined(separator: " · ")
        case .title:
            var parts: [String] = []
            if let date = hit.date {
                parts.append(describer.relativeDay(date, now: now))
            } else if !reminder.placeIDs.isEmpty {
                parts.append(describer.placeText(reminder, places: store.places))
            }
            if let rule = reminder.schedule?.rule {
                parts.append(describer.repeatText(rule))
            }
            return parts.joined(separator: " · ")
        }
    }

    private func highlighted(_ text: String, done: Bool) -> AttributedString {
        var result = AttributedString(text)
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return result }
        var start = text.startIndex
        while start < text.endIndex,
              let found = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: start..<text.endIndex, locale: locale) {
            if let lower = AttributedString.Index(found.lowerBound, within: result), let upper = AttributedString.Index(found.upperBound, within: result) {
                result[lower..<upper].backgroundColor = Palette.accent.opacity(done ? 0.12 : 0.18)
                if !done {
                    result[lower..<upper].underlineStyle = Text.LineStyle(pattern: .solid, color: Palette.accent)
                }
            }
            start = found.upperBound
        }
        return result
    }
}
