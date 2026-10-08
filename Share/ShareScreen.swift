import RemaCore
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

struct ShareScreen: View {
    let source: String
    let snapshot: StoreSnapshot?
    let onCancel: () -> Void
    let onSaved: () -> Void

    enum RepeatChoice: Equatable {
        case parsed
        case off
        case on(RepeatRule)
    }

    final class Memo {
        var text: String?
        var minute: Int?
        var parsed: ParsedPhrase?
        var pieces: [PhrasePiece]?
    }

    @State private var text: String
    @State private var schedule: Schedule?
    @State private var leads: [Int]?
    @State private var repeatChoice = RepeatChoice.parsed
    @State private var urgent: Bool?
    @State private var focused = false
    @State private var saving = false
    @State private var memo = Memo()
    @State private var removed: Set<Int> = []
    @State private var removedFor = ""
    @State private var keptWhole: String?

    // A sheet left open for a while still reads «in 5 minutes» from the real current minute.
    private var now: Date { Date() }
    private let calendar = Calendar.current
    private let locale = Locale.app

    init(source: String, snapshot: StoreSnapshot?, onCancel: @escaping () -> Void, onSaved: @escaping () -> Void) {
        self.source = source
        self.snapshot = snapshot
        self.onCancel = onCancel
        self.onSaved = onSaved
        _text = State(initialValue: Self.phrase(from: source, parser: Self.parser(snapshot: snapshot, now: Date())))
    }

    // A shared message is usually several sentences; the ones with a date are worth remembering, several of them become several reminders.
    static func phrase(from source: String, parser: PhraseParser) -> String {
        let limited = String(source.prefix(2_000))
        var sentences: [String] = []
        for line in limited.components(separatedBy: .newlines) {
            line.enumerateSubstrings(in: line.startIndex..., options: .bySentences) { sentence, _, _, _ in
                if let sentence = sentence?.trimmingCharacters(in: CharacterSet(charactersIn: ".!;").union(.whitespacesAndNewlines)), !sentence.isEmpty {
                    sentences.append(sentence)
                }
            }
        }
        let dated = sentences.filter { parser.parse($0).schedule != nil }
        // Sentences are joined only when each of them then becomes its own reminder; otherwise the first one with a date stays.
        if dated.count >= 2 {
            let joined = String(dated.prefix(10).joined(separator: "; ").prefix(1_000))
            if let pieces = parser.pieces(joined), pieces.count >= 2 {
                return joined
            }
        }
        let flat = limited.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = dated.first ?? flat
        let trimmed = chosen.trimmingCharacters(in: CharacterSet(charactersIn: ".!").union(.whitespaces))
        return String(trimmed.prefix(Reminder.maximumTitleLength))
    }

    private static func parser(snapshot: StoreSnapshot?, now: Date) -> PhraseParser {
        let settings = snapshot?.settings ?? .standard(at: now)
        var parser = PhraseParser(
            now: now,
            calendar: .current,
            morning: settings.morning,
            evening: settings.evening,
            places: places(in: snapshot).map(\.name),
            preferred: AppFonts.languageCode
        )
        parser.coordinate = places(in: snapshot).first.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
        if let data = try? Data(contentsOf: SharedStore.directory.appendingPathComponent("phrase-words.json")),
           let words = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            parser.languageSynonyms = words
        }
        return parser
    }

    private static func places(in snapshot: StoreSnapshot?) -> [Place] {
        snapshot?.places.filter { $0.deletedAt == nil && $0.remembered } ?? []
    }

    private var settings: Settings {
        snapshot?.settings ?? .standard(at: now)
    }

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    private var parsed: ParsedPhrase {
        let minute = Int(now.timeIntervalSince1970 / 60)
        if memo.text == text, memo.minute == minute, let parsed = memo.parsed {
            return parsed
        }
        let parser = Self.parser(snapshot: snapshot, now: now)
        let parsed = parser.parse(text)
        memo.text = text
        memo.minute = minute
        memo.parsed = parsed
        memo.pieces = parser.pieces(text)
        return parsed
    }

    private var pieces: [(index: Int, piece: PhrasePiece)]? {
        _ = parsed
        guard keptWhole != text, let all = memo.pieces else { return nil }
        let gone = removedFor == text ? removed : []
        return all.enumerated().filter { !gone.contains($0.offset) }.map { (index: $0.offset, piece: $0.element) }
    }

    private func pieceReminder(_ parsed: ParsedPhrase) -> Reminder {
        let places = Self.places(in: snapshot)
        return Reminder(
            title: String(parsed.title.prefix(Reminder.maximumTitleLength)),
            schedule: parsed.schedule,
            preAlerts: parsed.preAlerts,
            nag: parsed.nag,
            urgent: parsed.urgent,
            placeIDs: parsed.placeNames.compactMap { name in places.first { $0.name == name }?.id },
            placeTrigger: parsed.placeTrigger ?? .arrive,
            createdAt: now
        )
    }

    private func multiList(_ pieces: [(index: Int, piece: PhrasePiece)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(verbatim: String(localized: "You'll get \(pieces.count) reminders", bundle: .app, locale: .app))
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            if !pieces.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(pieces.enumerated()), id: \.element.index) { position, entry in
                        pieceRow(entry.index, entry.piece)
                        if position < pieces.count - 1 {
                            Hairline()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .panel()
            }
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(Motion.standard) { keptWhole = text }
            } label: {
                Text(verbatim: String(localized: "Keep as one reminder", bundle: .app, locale: .app))
                    .font(.app(.golos, 15, weight: 600))
                    .foregroundStyle(Palette.accentText)
                    .frame(height: 40)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(RowPressStyle())
            .padding(.top, 6)
        }
    }

    private func pieceRow(_ index: Int, _ piece: PhrasePiece) -> some View {
        let schedule = piece.parsed.schedule
        let date = schedule.flatMap { Recurrence.next($0, after: now.addingTimeInterval(-60), limit: 1, calendar: calendar).first }
        let line = schedule?.rule.map(describer.repeatText) ?? date.map { describer.dayTitle($0).lowercased(with: locale) } ?? ""
        return HStack(spacing: 14) {
            Text(verbatim: date.map(describer.time) ?? "")
                .font(.app(.jost, 22, weight: 500))
                .monospacedDigit()
                .timeColumn(size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: piece.parsed.title)
                    .font(.app(.golos, 16, weight: 600))
                    .lineLimit(2)
                Text(verbatim: line)
                    .font(.app(.golos, 12))
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(Motion.standard) {
                    if removedFor != text {
                        removedFor = text
                        removed = []
                    }
                    removed.insert(index)
                    if pieces?.isEmpty == true {
                        keptWhole = text
                    }
                }
            } label: {
                Glyph(paths: Icons.close, size: 16, lineWidth: 2, color: Palette.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PressableStyle())
            .padding(.trailing, -10)
            .accessibilityLabel(Text(verbatim: String(localized: "Remove \(piece.parsed.title)", bundle: .app, locale: .app)))
        }
        .frame(minHeight: 60)
    }

    private var reminder: Reminder {
        let result = parsed
        var plan = schedule ?? result.schedule
        switch repeatChoice {
        case .parsed:
            break
        case .off:
            plan?.rule = nil
        case .on(let rule):
            plan?.rule = rule
        }
        let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let places = Self.places(in: snapshot)
        return Reminder(
            title: String((title.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : title).prefix(Reminder.maximumTitleLength)),
            schedule: plan,
            preAlerts: leads ?? result.preAlerts,
            nag: result.nag,
            urgent: urgent ?? result.urgent,
            placeIDs: result.placeNames.compactMap { name in places.first { $0.name == name }?.id },
            placeTrigger: result.placeTrigger ?? .arrive,
            createdAt: now
        )
    }

    private var when: Date? {
        guard let plan = reminder.schedule else { return nil }
        return Recurrence.next(plan, after: now.addingTimeInterval(-60), limit: 1, calendar: calendar).first
    }

    private var canSave: Bool {
        !reminder.title.isEmpty && (when != nil || !reminder.placeIDs.isEmpty)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    phraseCard
                        .padding(.top, 12)
                    if excerpt != text {
                        sourceLine
                            .padding(.top, 8)
                    }
                    if let pieces {
                        multiList(pieces)
                            .padding(.top, 14)
                    } else {
                        whenCard
                            .padding(.top, 12)
                        options
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            PrimaryBar(action: save) {
                Text(verbatim: pieces.map { String(localized: "Save \($0.count)", bundle: .app, locale: .app) } ?? confirmTitle)
                    .contentTransition(.numericText())
            }
            .disabled((pieces.map(\.isEmpty) ?? !canSave) || saving)
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: when)
        .animation(Motion.standard, value: reminder.placeIDs)
    }

    // The name stays in the middle whatever the length of «Cancel» in the language.
    private var header: some View {
        ZStack {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .circular)
                        .fill(cssGradient(160, [Palette.dialBezelTop, Palette.dialBezelBottom]).shadow(.drop(color: Palette.dialShadowNear, radius: 1, y: 1)))
                    MiniDial(hour: 10, minute: 10, size: 20)
                }
                .frame(width: 26, height: 26)
                Text(verbatim: "Rema")
                    .font(.app(.jost, 18, weight: 500))
            }
            HStack {
                Button(action: onCancel) {
                    Text(verbatim: String(localized: "Cancel", bundle: .app, locale: .app))
                        .font(.app(.golos, 16))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .frame(height: 44, alignment: .leading)
                }
                .buttonStyle(RowPressStyle())
                Spacer(minLength: 8)
            }
        }
    }

    private var phraseCard: some View {
        PhraseField(text: $text, highlights: parsed.highlights, focused: $focused)
            .frame(minHeight: 64, alignment: .topLeading)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .accessibilityLabel(Text(verbatim: String(localized: "What and when to remind", bundle: .app, locale: .app)))
    }

    private var excerpt: String {
        source.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sourceLine: some View {
        HStack(spacing: 6) {
            Glyph(paths: Icons.message, size: 14, lineWidth: 2, color: Palette.secondary)
            Text(verbatim: excerpt.quoted())
                .font(.app(.golos, 13))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var whenCard: some View {
        if let when {
            let parts = calendar.dateComponents([.hour, .minute], from: when)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel(verbatim: String(localized: "I'll remind", bundle: .app, locale: .app))
                    Text(verbatim: describer.time(when))
                        .font(.app(.jost, 44, weight: 500))
                        .frame(height: 48)
                        .contentTransition(.numericText())
                    Text(verbatim: describer.dayTitle(when))
                        .font(.app(.golos, 15, weight: 600))
                    Text(verbatim: [distance(to: when), reminder.title].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MiniDial(hour: parts.hour ?? 0, minute: parts.minute ?? 0, size: 88)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .panel()
            .transition(.opacity)
        } else if reminder.placeIDs.isEmpty {
            let tonight = date(on: now, at: settings.evening)
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(verbatim: String(localized: "When to remind?", bundle: .app, locale: .app))
                FlowLayout(spacing: 8) {
                    quickTime("In an hour", now.addingTimeInterval(3600))
                    if tonight.timeIntervalSince(now) > 15 * 60 {
                        quickTime("Tonight", tonight)
                    }
                    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                        quickTime("Tomorrow morning", date(on: tomorrow, at: settings.morning))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .transition(.opacity)
        }
    }

    private var options: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach([15, 60, 1_440], id: \.self) { minutes in
                    Button {
                        let current = reminder.preAlerts
                        leads = current.contains(minutes) ? current.filter { $0 != minutes } : (current + [minutes]).sorted()
                    } label: {
                        menuLabel(describer.leadText(minutes).capitalizedFirst(locale), checked: reminder.preAlerts.contains(minutes))
                    }
                }
            } label: {
                chipLabel("In advance", selected: !reminder.preAlerts.isEmpty)
            }
            .disabled(when == nil)
            Menu {
                ForEach(Array(repeatOptions.enumerated()), id: \.offset) { _, option in
                    Button {
                        repeatChoice = reminder.schedule?.rule == option.rule ? .off : .on(option.rule)
                    } label: {
                        menuLabel(option.title, checked: reminder.schedule?.rule == option.rule)
                    }
                }
            } label: {
                chipLabel("Repeat", selected: reminder.schedule?.rule != nil)
            }
            .disabled(when == nil)
            Button {
                urgent = !reminder.urgent
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                chipLabel("Urgent", selected: reminder.urgent)
            }
            .buttonStyle(PressableStyle())
        }
        .animation(Motion.small, value: reminder.urgent)
    }

    private var repeatOptions: [(title: String, rule: RepeatRule)] {
        guard let when else { return [] }
        let day = LocalDate(when, in: calendar)
        return [
            (String(localized: "Every day", bundle: .app, locale: .app), .daily),
            (String(localized: "Every week", bundle: .app, locale: .app), .weekly([day.weekday])),
            (String(localized: "Every month", bundle: .app, locale: .app), .monthlyOnDay(day.day)),
            (String(localized: "Every year", bundle: .app, locale: .app), .yearly(month: day.month, day: day.day)),
        ]
    }

    @ViewBuilder
    private func menuLabel(_ title: String, checked: Bool) -> some View {
        if checked {
            Label(title, systemImage: "checkmark")
        } else {
            Text(verbatim: title)
        }
    }

    private func chipLabel(_ title: String.LocalizationValue, selected: Bool) -> some View {
        HStack(spacing: 6) {
            Glyph(paths: selected ? Icons.check : Icons.plus, size: 14, lineWidth: 2.4, color: selected ? Palette.onSegment : Palette.text)
            Text(verbatim: String(localized: title, bundle: .app, locale: .app))
                .font(.app(.golos, 14, weight: 600))
        }
        .foregroundStyle(selected ? Palette.onSegment : Palette.text)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .circular)
                .fill(selected ? Palette.segment : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .circular)
                .strokeBorder(Palette.text, lineWidth: selected ? 0 : 1.5)
        }
        .contentShape(Rectangle())
    }

    private func quickTime(_ title: String.LocalizationValue, _ date: Date) -> some View {
        Button {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            schedule = Schedule(start: LocalDate(date, in: calendar), time: LocalTime(hour: parts.hour ?? 9, minute: parts.minute ?? 0))
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: String(localized: title, bundle: .app, locale: .app))
                Text(verbatim: describer.shortTime(date))
                    .font(.app(.jost, 15, weight: 500))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .buttonStyle(RaisedChipStyle())
    }

    private func date(on day: Date, at time: LocalTime) -> Date {
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) ?? day
    }

    private func distance(to date: Date) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1:
            return describer.countdown(from: now, to: date)
        case 1:
            return String(localized: "tomorrow", bundle: .app, locale: .app)
        default:
            return String(localized: "in \(days) days", bundle: .app, locale: .app)
        }
    }

    private var confirmTitle: String {
        if let when {
            return String(localized: "Remind \(describer.dayAndTime(when, now: now))", bundle: .app, locale: .app)
        }
        if !reminder.placeIDs.isEmpty {
            return String(localized: "Remind by place", bundle: .app, locale: .app)
        }
        return String(localized: "Choose a time", bundle: .app, locale: .app)
    }

    private func save() {
        let chosen: [Reminder]
        if let pieces {
            chosen = pieces.map { pieceReminder($0.piece.parsed) }
        } else {
            chosen = canSave ? [reminder] : []
        }
        guard !chosen.isEmpty, !saving else { return }
        saving = true
        let items = chosen.map { item -> Reminder in
            var stamped = item
            stamped.updatedAt = Date()
            return stamped
        }
        var store = SharedStore.load() ?? StoreSnapshot(reminders: [], places: [], settings: settings, sounds: nil)
        store.reminders.append(contentsOf: items)
        guard (try? SharedStore.save(store)) != nil else {
            saving = false
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        WidgetCenter.shared.reloadAllTimelines()
        let settings = store.settings
        let describer = self.describer
        Task {
            for item in items {
                await QuickNotifications.schedule(item, settings: settings, describer: describer)
            }
            onSaved()
        }
    }
}
