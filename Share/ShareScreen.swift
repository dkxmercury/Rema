import RemaCore
import SwiftUI
import UIKit
import UserNotifications

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
        var parsed: ParsedPhrase?
    }

    @State private var text: String
    @State private var schedule: Schedule?
    @State private var leads: [Int]?
    @State private var repeatChoice = RepeatChoice.parsed
    @State private var urgent: Bool?
    @State private var focused = false
    @State private var saving = false
    @State private var memo = Memo()

    private let now = Date()
    private let calendar = Calendar.current
    private let locale = Locale.current

    init(source: String, snapshot: StoreSnapshot?, onCancel: @escaping () -> Void, onSaved: @escaping () -> Void) {
        self.source = source
        self.snapshot = snapshot
        self.onCancel = onCancel
        self.onSaved = onSaved
        _text = State(initialValue: Self.phrase(from: source, parser: Self.parser(snapshot: snapshot, now: Date())))
    }

    // A shared message is usually several sentences; the one with a date is the one worth remembering.
    static func phrase(from source: String, parser: PhraseParser) -> String {
        let flat = source.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        var sentences: [String] = []
        flat.enumerateSubstrings(in: flat.startIndex..., options: .bySentences) { sentence, _, _, _ in
            if let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        let chosen = sentences.first { parser.parse($0).schedule != nil } ?? flat
        let trimmed = chosen.trimmingCharacters(in: CharacterSet(charactersIn: ".!").union(.whitespaces))
        return String(trimmed.prefix(Reminder.maximumTitleLength))
    }

    private static func parser(snapshot: StoreSnapshot?, now: Date) -> PhraseParser {
        let settings = snapshot?.settings ?? .standard(at: now)
        return PhraseParser(
            now: now,
            calendar: .current,
            morning: settings.morning,
            evening: settings.evening,
            places: places(in: snapshot).map(\.name),
            preferred: Bundle.main.preferredLocalizations.first
        )
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
        if memo.text == text, let parsed = memo.parsed {
            return parsed
        }
        let parsed = Self.parser(snapshot: snapshot, now: now).parse(text)
        memo.text = text
        memo.parsed = parsed
        return parsed
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
            title: title.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : title,
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
                    whenCard
                        .padding(.top, 12)
                    options
                        .padding(.top, 12)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            PrimaryBar(action: save) {
                Text(verbatim: confirmTitle)
                    .contentTransition(.numericText())
            }
            .disabled(!canSave || saving)
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: when)
        .animation(Motion.standard, value: reminder.placeIDs)
    }

    private var header: some View {
        HStack {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.app(.golos, 16))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 76, height: 44, alignment: .leading)
            }
            .buttonStyle(RowPressStyle())
            Spacer(minLength: 8)
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
            Spacer(minLength: 8)
            Color.clear
                .frame(width: 76, height: 44)
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
            .accessibilityLabel(Text("What and when to remind"))
    }

    private var excerpt: String {
        source.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sourceLine: some View {
        HStack(spacing: 6) {
            Glyph(paths: Icons.message, size: 14, lineWidth: 2, color: Palette.secondary)
            Text(verbatim: "«\(excerpt)»")
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
                    SectionLabel(text: "I'll remind")
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
                SectionLabel(text: "When to remind?")
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
            (String(localized: "Every day"), .daily),
            (String(localized: "Every week"), .weekly([day.weekday])),
            (String(localized: "Every month"), .monthlyOnDay(day.day)),
            (String(localized: "Every year"), .yearly(month: day.month, day: day.day)),
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

    private func chipLabel(_ title: LocalizedStringKey, selected: Bool) -> some View {
        HStack(spacing: 6) {
            Glyph(paths: selected ? Icons.check : Icons.plus, size: 14, lineWidth: 2.4, color: selected ? Palette.onSegment : Palette.text)
            Text(title)
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

    private func quickTime(_ title: LocalizedStringKey, _ date: Date) -> some View {
        Button {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            schedule = Schedule(start: LocalDate(date, in: calendar), time: LocalTime(hour: parts.hour ?? 9, minute: parts.minute ?? 0))
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 8) {
                Text(title)
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
            return String(localized: "tomorrow")
        default:
            return String(localized: "in \(days) days")
        }
    }

    private var confirmTitle: String {
        if let when {
            return String(localized: "Remind \(describer.dayAndTime(when, now: now))")
        }
        if !reminder.placeIDs.isEmpty {
            return String(localized: "Remind by place")
        }
        return String(localized: "Choose a time")
    }

    private func save() {
        guard canSave, !saving else { return }
        saving = true
        var item = reminder
        item.updatedAt = Date()
        var store = SharedStore.load() ?? StoreSnapshot(reminders: [], places: [], settings: settings, sounds: nil)
        store.reminders.append(item)
        guard (try? SharedStore.save(store)) != nil else {
            saving = false
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let settings = store.settings
        let describer = self.describer
        Task {
            await ShareNotifications.schedule(item, settings: settings, describer: describer)
            onSaved()
        }
    }
}

// The app rebuilds every notification on its next launch; until then this keeps the new reminder from going silent.
enum ShareNotifications {
    static func schedule(_ reminder: Reminder, settings: Settings, describer: Describer) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let plan = Scheduler.plan(reminders: [reminder], settings: settings, now: Date(), calendar: .current, capacity: 8)
        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            let when = describer.dayAndTime(item.occurrence, now: item.fireDate).capitalizedFirst(describer.locale)
            if case .early = item.kind {
                content.body = String(localized: "\(when), reminding in advance")
            } else {
                content.body = when
            }
            content.sound = .default
            content.categoryIdentifier = item.nag ? "nag" : "reminder"
            content.threadIdentifier = item.reminderID.uuidString
            content.userInfo = ["reminder": item.reminderID.uuidString, "occurrence": item.occurrence.timeIntervalSince1970]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        }
    }
}
