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
    var locale: Locale = .current
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

    struct Overrides: Equatable {
        var urgent: Bool?
        var schedule: Schedule?
        var preAlerts: [Int]?
        var sound: SoundChoice?
        var placeIDs: [UUID]?
        var placeTrigger: PlaceTrigger?
    }

    init(store: Store, text: String = "", now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current, startWithVoice: Bool = false, autofocus: Bool = true, onClose: @escaping () -> Void) {
        self.store = store
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.startWithVoice = startWithVoice
        self.autofocus = autofocus
        self.onClose = onClose
        _text = State(initialValue: text)
        _draft = State(initialValue: Reminder(title: "", schedule: nil, createdAt: now))
        _listening = State(initialValue: startWithVoice)
    }

    private var parser: PhraseParser {
        PhraseParser(now: now, calendar: calendar, morning: store.settings.morning, evening: store.settings.evening, places: store.activePlaces.map(\.name))
    }

    private var parsed: ParsedPhrase {
        parser.parse(text)
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
                    NewPlaceScreen(store: store, onSaved: { place in
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
        let phrase = spoken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
                    ScreenHeader(title: "New reminder", leading: .close, action: onClose) {
                        RoundIconButton(icon: Icons.microphone, iconSize: 19, label: "Dictate") {
                            focused = false
                            listening = true
                        }
                    }
                    input
                        .padding(.top, 14)
                    ReminderPreview(when: when, place: placeLine, summary: summaryLine, summaryLines: 2, describer: describer, calendar: calendar)
                        .contentShape(Rectangle())
                        .onTapGesture { pickingDate = true }
                        .padding(.top, 12)
                    addOns
                        .padding(.top, 12)
                    examples
                        .padding(.top, 14)
                }
                .padding(.horizontal, 18)
                .padding(.top, 15)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            PrimaryBar(action: confirm) {
                Text(verbatim: confirmTitle)
                    .contentTransition(.numericText())
            }
            .disabled(parsed.title.isEmpty)
            .opacity(parsed.title.isEmpty ? 0.6 : 1)
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: text)
        .animation(Motion.standard, value: overrides)
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
            return placeLine == nil ? String(localized: "for example, tomorrow at 9") : title
        }
        let countdown = describer.countdown(from: now, to: when)
        return title.isEmpty ? countdown : "\(countdown) · \(title)"
    }

    private var addOns: some View {
        FlowLayout(spacing: 8) {
            Chip(title: "Repeat", selected: reminder.schedule?.rule != nil, icon: Icons.plus) { path.append(.repeating) }
            Chip(title: "In advance", selected: !reminder.preAlerts.isEmpty, icon: Icons.plus) { path.append(.early) }
            Chip(title: "Place", selected: !reminder.placeIDs.isEmpty, icon: Icons.plus) { path.append(.places) }
            Chip(title: "Urgent", selected: reminder.urgent, icon: Icons.plus) {
                overrides.urgent = !reminder.urgent
                Feedback.play(.toggle)
            }
            Chip(title: "Sound", selected: overrides.sound != nil, icon: Icons.plus) { path.append(.sound) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var examples: some View {
        let samples = [
            String(localized: "in 2 hours"),
            String(localized: "on Friday evening"),
            String(localized: "every Tue and Thu at 8"),
            String(localized: "every year on October 12"),
            String(localized: "when I leave work"),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "You can write like this")
                .padding(.bottom, 4)
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
                        Text(verbatim: exampleValue(sample))
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
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .panel()
    }

    private func exampleIsPlace(_ sample: String) -> Bool {
        sample.hasPrefix("когда") || sample.hasPrefix("when")
    }

    private func exampleValue(_ sample: String) -> String {
        let result = parser.parse(sample)
        if result.placeTrigger != nil || exampleIsPlace(sample) {
            let name = result.placeNames.first ?? String(localized: "Work")
            return String(localized: "by place · \(name)")
        }
        guard let schedule = result.schedule,
              let date = Recurrence.next(schedule, after: now.addingTimeInterval(-60), limit: 1, calendar: calendar).first else { return "" }
        switch schedule.rule {
        case .weekly(let days):
            return "\(describer.weekdayList(days)) · \(describer.shortTime(date))"
        case .yearly:
            let day = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)).replacingOccurrences(of: ".", with: "")
            return String(localized: "yearly, \(day)")
        default:
            if calendar.isDate(date, inSameDayAs: now) {
                return String(localized: "today, \(describer.shortTime(date))")
            }
            var symbols = calendar
            symbols.locale = locale
            let weekday = symbols.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
            let day = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)).replacingOccurrences(of: ".", with: "")
            return "\(weekday) \(day), \(describer.shortTime(date))"
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

    private func confirm() {
        guard !parsed.title.isEmpty else { return }
        guard reminder.schedule != nil || !reminder.placeIDs.isEmpty else {
            pickingDate = true
            return
        }
        Feedback.play(.save)
        store.save(reminder)
        Notifier.shared.requestPermissionIfNeeded()
        onClose()
    }
}
