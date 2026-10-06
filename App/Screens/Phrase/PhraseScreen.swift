import RemaCore
import SwiftUI

enum PhraseRoute: Hashable {
    case repeating
    case early
    case sound
    case places
    case newPlace
}

struct PhraseScreen: View {
    let store: Store
    var now: Date = Date()
    var calendar: Calendar = .current
    var locale: Locale = AppLanguage.current.locale
    var startWithVoice = false
    var autofocus = true
    let onClose: () -> Void

    @State private var text: String
    @State private var overrides = Overrides()
    @State private var path: [PhraseRoute] = []
    @State private var draft: Reminder
    @State private var listening: Bool
    @State private var pickingDate = false
    @State private var focused = false
    @State private var memo = Memo()
    @State private var keyboardShown = false
    @State private var recentPhrases = RecentPhrases.all
    @State private var showingExamples = false
    @State private var earlyDismissed = false

    // Body reads the parse result a dozen times per keystroke; parsing once per text keeps typing smooth.
    final class Memo {
        struct Key: Equatable {
            var text: String
            var places: [String]
            var morning: LocalTime
            var evening: LocalTime
        }

        var key: Key?
        var parsed: ParsedPhrase?
        var examples: [String: String] = [:]
    }

    struct Overrides: Equatable {
        var urgent: Bool?
        var schedule: Schedule?
        var preAlerts: [Int]?
        var sound: SoundChoice?
        var placeIDs: [UUID]?
        var placeTrigger: PlaceTrigger?
    }

    init(store: Store, text: String = "", now: Date = Date(), calendar: Calendar = .current, locale: Locale = AppLanguage.current.locale, startWithVoice: Bool = false, autofocus: Bool = true, onClose: @escaping () -> Void) {
        self.store = store
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.startWithVoice = startWithVoice
        self.autofocus = autofocus
        self.onClose = onClose
        _text = State(initialValue: text)
        _draft = State(initialValue: Reminder(title: "", schedule: nil, createdAt: now))
        _listening = State(initialValue: startWithVoice && VoiceRecognizer.available)
    }

    private var parser: PhraseParser {
        PhraseParser(now: now, calendar: calendar, morning: store.settings.morning, evening: store.settings.evening, places: store.activePlaces.map(\.name), preferred: AppLanguage.current.rawValue)
    }

    private var parsed: ParsedPhrase {
        let key = Memo.Key(text: text, places: store.activePlaces.map(\.name), morning: store.settings.morning, evening: store.settings.evening)
        if memo.key == key, let parsed = memo.parsed {
            return parsed
        }
        let parsed = parser.parse(text)
        memo.key = key
        memo.parsed = parsed
        return parsed
    }

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    private var reminder: Reminder {
        let result = parsed
        var reminder = Reminder(
            title: result.title,
            schedule: overrides.schedule ?? result.schedule,
            preAlerts: overrides.preAlerts ?? result.preAlerts,
            nag: result.nag,
            urgent: overrides.urgent ?? result.urgent,
            placeIDs: overrides.placeIDs ?? result.placeNames.compactMap { name in store.activePlaces.first { $0.name == name }?.id },
            placeTrigger: overrides.placeTrigger ?? result.placeTrigger ?? .arrive,
            sound: overrides.sound ?? .standard,
            createdAt: now
        )
        reminder.id = draft.id
        return reminder
    }

    private var when: Date? {
        guard let schedule = reminder.schedule else { return nil }
        return Recurrence.next(schedule, after: now.addingTimeInterval(-60), limit: 1, calendar: calendar).first
    }

    var body: some View {
        ZStack {
            PushStack(path: $path) {
                content
            } destination: { route in
                switch route {
                case .repeating:
                    RepeatScreen(draft: draftBinding, now: now, calendar: calendar, locale: locale) { path.removeLast() }
                case .early:
                    EarlyScreen(draft: draftBinding, now: now, calendar: calendar, locale: locale) { path.removeLast() }
                case .sound:
                    SoundScreen(store: store, choice: soundBinding, locale: locale) { path.removeLast() }
                case .places:
                    PlacesScreen(store: store, title: parsed.title, placeIDs: placesBinding, trigger: triggerBinding, onNewPlace: { path.append(.newPlace) }, onBack: { path.removeLast() })
                case .newPlace:
                    NewPlaceScreen(store: store, askToRemember: true, onSaved: { place in
                        overrides.placeIDs = reminder.placeIDs + [place.id]
                        path.removeLast()
                    }, onBack: { path.removeLast() })
                }
            }
            if listening {
                VoiceScreen(store: store, now: now, calendar: calendar, locale: locale, onFinish: heard)
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
                    .zIndex(1)
            }
        }
        .animation(Motion.standard, value: listening)
        .fullScreenCover(isPresented: $pickingDate) {
            DateTimeScreen(initial: when ?? now.addingTimeInterval(3600), now: now, settings: store.settings, calendar: calendar, locale: locale, onDone: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                var schedule = reminder.schedule ?? Schedule(start: LocalDate(date, in: calendar), time: LocalTime(hour: 9, minute: 0))
                schedule.start = LocalDate(date, in: calendar)
                schedule.time = LocalTime(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
                overrides.schedule = schedule
                pickingDate = false
            }, onClose: { pickingDate = false })
        }
        .onAppear {
            if !listening, autofocus {
                focused = true
            }
        }
    }

    private func heard(_ spoken: String?) {
        let phrase = String((spoken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").prefix(Reminder.maximumTitleLength))
        if !phrase.isEmpty {
            text = phrase
            listening = false
        } else if text.isEmpty, startWithVoice {
            onClose()
        } else {
            listening = false
            focused = true
        }
    }

    private var placesBinding: Binding<[UUID]> {
        Binding(get: { reminder.placeIDs }, set: { overrides.placeIDs = $0 })
    }

    private var triggerBinding: Binding<PlaceTrigger> {
        Binding(get: { reminder.placeTrigger }, set: { overrides.placeTrigger = $0 })
    }

    private var soundBinding: Binding<SoundChoice> {
        Binding(get: { reminder.sound }, set: { overrides.sound = $0 })
    }

    private var draftBinding: Binding<Reminder> {
        Binding(
            get: { reminder },
            set: { updated in
                overrides.schedule = updated.schedule
                overrides.preAlerts = updated.preAlerts
            }
        )
    }

    private var content: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    input
                        .padding(.top, 14)
                    ReminderPreview(when: when, place: placeLine, summary: summaryLine, summaryLines: 2, describer: describer, calendar: calendar)
                        .contentShape(Rectangle())
                        .onTapGesture { pickingDate = true }
                        .padding(.top, 12)
                    if let suggestion = earlySuggestion {
                        EarlySuggestionCard(suggestion: suggestion) {
                            overrides.preAlerts = (reminder.preAlerts + [suggestion.minutes]).sorted()
                            Feedback.play(.select)
                        } onDismiss: {
                            earlyDismissed = true
                        }
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    addOns
                        .padding(.top, 12)
                    suggestions
                        .padding(.top, 14)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .pinnedHeader {
                ScreenHeader(title: "New reminder", leading: .close, action: onClose) {
                    if VoiceRecognizer.available {
                        RoundIconButton(icon: Icons.microphone, iconSize: 19, label: "Dictate") {
                            focused = false
                            listening = true
                        }
                    }
                }
            }
            PrimaryBar(action: confirm) {
                Text(verbatim: confirmTitle)
                    .contentTransition(.numericText())
            }
            .disabled(parsed.title.isEmpty)
            if showsQuickTimes {
                quickTimes
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: showsQuickTimes)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardShown = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardShown = false }
        .animation(Motion.standard, value: when)
        .animation(Motion.standard, value: reminder.placeIDs)
        .animation(Motion.standard, value: overrides)
        .animation(Motion.standard, value: earlySuggestion)
    }

    private var earlySuggestion: EarlySuggestion? {
        guard !earlyDismissed, Remote.shared.isOn(.suggestions), let when else { return nil }
        return Suggestions.early(title: parsed.title, when: when, preAlerts: reminder.preAlerts, now: now)
    }

    private var input: some View {
        PhraseField(text: $text, highlights: parsed.highlights, focused: $focused, onSubmit: confirm)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("What and when to remind?")
                        .font(.app(.golos, 24, weight: 600))
                        .foregroundStyle(Palette.faint)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 64, alignment: .topLeading)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .overlay(alignment: .bottomTrailing) {
                if text.count >= Reminder.maximumTitleLength - 40 {
                    Text(verbatim: "\(text.count)/\(Reminder.maximumTitleLength)")
                        .font(.app(.golos, 12, weight: 500))
                        .monospacedDigit()
                        .foregroundStyle(text.count >= Reminder.maximumTitleLength ? Palette.accentText : Palette.secondary)
                        .padding(.trailing, 14)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .accessibilityLabel(Text("What and when to remind"))
    }

    private var placeLine: String? {
        reminder.placeIDs.isEmpty ? nil : describer.placeText(reminder, places: store.places)
    }

    private var summaryLine: String {
        let title = parsed.title.lowercased(with: locale)
        guard let when else {
            if placeLine == nil, keyboardShown, !parsed.title.isEmpty {
                return String(localized: "or pick an option above the keyboard", locale: .app)
            }
            return placeLine == nil ? String(localized: "for example, tomorrow at 9", locale: .app) : title
        }
        let countdown = describer.countdown(from: now, to: when)
        return title.isEmpty ? countdown : "\(countdown) · \(title)"
    }

    private var addOns: some View {
        FlowLayout(spacing: 8) {
            Chip(title: "Repeat", selected: reminder.schedule?.rule != nil, icon: Icons.plus) { path.append(.repeating) }
            Chip(title: "In advance", selected: !reminder.preAlerts.isEmpty, icon: Icons.plus) { path.append(.early) }
            if Remote.shared.isOn(.places) {
                Chip(title: "Place", selected: !reminder.placeIDs.isEmpty, icon: Icons.plus) { path.append(.places) }
            }
            Chip(title: "Urgent", selected: reminder.urgent, icon: Icons.plus) {
                overrides.urgent = !reminder.urgent
                Feedback.play(.toggle)
            }
            Chip(title: "Sound", selected: overrides.sound != nil, icon: Icons.plus) { path.append(.sound) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exampleSamples: [String] {
        Remote.shared.exampleOverride ?? [
            String(localized: "in 2 hours", locale: .app),
            String(localized: "on Friday evening", locale: .app),
            String(localized: "every Tue and Thu at 8", locale: .app),
            String(localized: "every year on October 12", locale: .app),
            String(localized: "when I leave work", locale: .app),
        ]
    }

    private var showsRecent: Bool {
        recentPhrases.count >= 2 && !showingExamples
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(text: showsRecent ? "You wrote recently" : "You can write like this")
                Spacer(minLength: 8)
                if recentPhrases.count >= 2 {
                    Button {
                        withAnimation(Motion.standard) { showingExamples.toggle() }
                        Feedback.play(.select)
                    } label: {
                        Text(showsRecent ? LocalizedStringKey("Examples") : LocalizedStringKey("Your phrases"))
                            .font(.app(.golos, 13, weight: 600))
                            .foregroundStyle(Palette.accentText)
                            .frame(height: 28)
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
            .padding(.bottom, 4)
            if showsRecent {
                recentRows
            } else {
                exampleRows
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, showsRecent ? 0 : 6)
        .panel()
    }

    private var recentRows: some View {
        let phrases = Array(recentPhrases.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(phrases.enumerated()), id: \.offset) { index, phrase in
                Button {
                    text = phrase
                    focused = true
                    Feedback.play(.select)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "«\(phrase)»")
                                .font(.app(.golos, 15))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            let value = cachedExampleValue(phrase)
                            if !value.isEmpty {
                                Text(verbatim: value)
                                    .font(.app(.golos, 13, weight: 500))
                                    .foregroundStyle(Palette.accentText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Glyph(paths: Icons.insert, size: 16, lineWidth: 2, color: Palette.secondary)
                    }
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                if index < phrases.count - 1 {
                    Hairline()
                }
            }
        }
    }

    private var exampleRows: some View {
        let samples = exampleSamples
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                Button {
                    text = sample
                    focused = true
                    Feedback.play(.select)
                } label: {
                    HStack(spacing: 12) {
                        Text(verbatim: "«\(sample)»")
                            .font(.app(.golos, 15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: cachedExampleValue(sample))
                            .font(exampleIsPlace(sample) ? .app(.golos, 15, weight: 500) : .app(.jost, 15, weight: 500))
                            .foregroundStyle(Palette.accentText)
                    }
                    .frame(minHeight: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                if index < samples.count - 1 {
                    Hairline()
                }
            }
        }
    }

    private var showsQuickTimes: Bool {
        keyboardShown && !parsed.title.isEmpty && reminder.schedule == nil && reminder.placeIDs.isEmpty
    }

    private var quickTimes: some View {
        let inAnHour = now.addingTimeInterval(3600)
        let tonight = date(on: now, at: store.settings.evening)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now).map { date(on: $0, at: store.settings.morning) }
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                quickTime("In an hour", inAnHour)
                if tonight.timeIntervalSince(now) > 15 * 60 {
                    quickTime("Tonight", tonight)
                }
                if let tomorrow {
                    quickTime("Tomorrow morning", tomorrow)
                }
                Button {
                    focused = false
                    pickingDate = true
                } label: {
                    HStack(spacing: 8) {
                        Glyph(paths: Icons.calendar, size: 16, lineWidth: 2, color: Palette.text)
                        Text("Another time")
                    }
                }
                .buttonStyle(RaisedChipStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .scrollIndicators(.hidden)
        .frame(height: 58)
        .background {
            Palette.background
                .overlay(alignment: .top) { Hairline() }
        }
    }

    private func quickTime(_ title: LocalizedStringKey, _ date: Date) -> some View {
        Button {
            Feedback.play(.select)
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            overrides.schedule = Schedule(start: LocalDate(date, in: calendar), time: LocalTime(hour: parts.hour ?? 9, minute: parts.minute ?? 0))
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

    private func exampleIsPlace(_ sample: String) -> Bool {
        ["когда", "коли", "when", "quand", "wenn", "عندما"].contains { sample.hasPrefix($0) } || sample.hasSuffix("ganimda") || sample.hasSuffix("ганимда")
    }

    private func cachedExampleValue(_ sample: String) -> String {
        if let value = memo.examples[sample] {
            return value
        }
        let value = exampleValue(sample)
        memo.examples[sample] = value
        return value
    }

    private func exampleValue(_ sample: String) -> String {
        let result = parser.parse(sample)
        if result.placeTrigger != nil || exampleIsPlace(sample) {
            let name = result.placeNames.first ?? String(localized: "Work", locale: .app)
            return String(localized: "by place · \(name)", locale: .app)
        }
        guard let schedule = result.schedule,
              let date = Recurrence.next(schedule, after: now.addingTimeInterval(-60), limit: 1, calendar: calendar).first else { return "" }
        switch schedule.rule {
        case .weekly(let days):
            return "\(describer.weekdayList(days)) · \(describer.shortTime(date))"
        case .yearly:
            let day = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)).replacingOccurrences(of: ".", with: "")
            return String(localized: "yearly, \(day)", locale: .app)
        default:
            if calendar.isDate(date, inSameDayAs: now) {
                return String(localized: "today, \(describer.shortTime(date))", locale: .app)
            }
            var symbols = calendar
            symbols.locale = locale
            var weekday = symbols.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
            if ["ru", "uk", "uz", "fr"].contains(locale.language.languageCode?.identifier ?? "") {
                weekday = weekday.lowercased(with: locale)
            }
            let day = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)).replacingOccurrences(of: ".", with: "")
            return "\(weekday) \(day), \(describer.shortTime(date))"
        }
    }

    private var confirmTitle: String {
        if let when {
            return String(localized: "Remind \(describer.dayAndTime(when, now: now))", locale: .app)
        }
        if !reminder.placeIDs.isEmpty {
            return String(localized: "Remind by place", locale: .app)
        }
        return String(localized: "Choose a time", locale: .app)
    }

    private func confirm() {
        guard !parsed.title.isEmpty else { return }
        guard reminder.schedule != nil || !reminder.placeIDs.isEmpty else {
            pickingDate = true
            return
        }
        Feedback.play(.save)
        store.save(reminder)
        RecentPhrases.remember(text)
        Notifier.shared.requestPermissionIfNeeded()
        onClose()
    }
}
