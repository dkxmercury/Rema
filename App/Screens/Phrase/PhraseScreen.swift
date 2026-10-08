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
    private let fixedNow: Date?
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
    @State private var flippedFor: String?
    @State private var keptWhole: String?
    @State private var shiftAnswered = false
    @State private var removed = Removed()
    @State private var listDeclined = false
    @State private var sharing = false
    @State private var sharedWith: [String] = []
    @State private var oneDone = false
    @State private var friendsService = SharedService.shared

    // Body reads the parse result a dozen times per keystroke; parsing once per text keeps typing smooth.
    final class Memo {
        struct Key: Equatable {
            var text: String
            var places: [String]
            var morning: LocalTime
            var evening: LocalTime
            var minute: Int
        }

        var key: Key?
        var parsed: ParsedPhrase?
        var examples: [String: String] = [:]
        var items: (title: String, items: [ChecklistItem])?
        var pieces: (key: Key, pieces: [PhrasePiece]?)?
    }

    struct Removed {
        var text = ""
        var indexes: Set<Int> = []
    }

    struct Overrides: Equatable {
        var urgent: Bool?
        var schedule: Schedule?
        var preAlerts: [Int]?
        var sound: SoundChoice?
        var placeIDs: [UUID]?
        var placeTrigger: PlaceTrigger?
        var items: [ChecklistItem]?
    }

    init(store: Store, text: String = "", now: Date? = nil, calendar: Calendar = .current, locale: Locale = AppLanguage.current.locale, startWithVoice: Bool = false, autofocus: Bool = true, onClose: @escaping () -> Void) {
        self.store = store
        self.fixedNow = now
        self.calendar = calendar
        self.locale = locale
        self.startWithVoice = startWithVoice
        self.autofocus = autofocus
        self.onClose = onClose
        _text = State(initialValue: text)
        _draft = State(initialValue: Reminder(title: "", schedule: nil, createdAt: now ?? Date()))
        _listening = State(initialValue: startWithVoice && VoiceRecognizer.available)
    }

    // A screen left open for a while still reads «in 5 minutes» from the real current minute.
    private var now: Date {
        fixedNow ?? Date()
    }

    private var parser: PhraseParser {
        store.phraseParser(now: now, calendar: calendar)
    }

    // The part of the day the phrase leaned on, and the time the person keeps choosing for it instead.
    private var partShift: (part: PartShift.Part, time: LocalTime)? {
        guard !shiftAnswered, let used = parsed.usedPart, overrides.schedule == nil else { return nil }
        let part: PartShift.Part
        if used == store.settings.evening {
            part = .evening
        } else if used == store.settings.morning {
            part = .morning
        } else {
            return nil
        }
        return PartShift.suggestion(part, current: used).map { (part, $0) }
    }

    private func partShiftCard(_ shift: (part: PartShift.Part, time: LocalTime)) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .circular)
        let clock = String(format: "%02d:%02d", shift.time.hour, shift.time.minute)
        return HStack(spacing: 10) {
            Glyph(paths: shift.part == .evening ? Icons.moon : Icons.sun, size: 22, lineWidth: 2, color: Palette.accentText)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: shift.part == .evening ? String(localized: "Make \(clock) your evening?", bundle: .app, locale: .app) : String(localized: "Make \(clock) your morning?", bundle: .app, locale: .app))
                    .font(.app(.golos, 15, weight: 600))
                Text("You often move it to this time")
                    .font(.app(.golos, 13))
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Feedback.play(.select)
                store.update { settings in
                    if shift.part == .evening {
                        settings.evening = shift.time
                    } else {
                        settings.morning = shift.time
                    }
                }
                PartShift.reset(shift.part)
            } label: {
                Text("Yes")
            }
            .buttonStyle(SmallButtonStyle(prominent: false))
            Button {
                PartShift.reset(shift.part)
                withAnimation(Motion.standard) { shiftAnswered = true }
            } label: {
                Glyph(paths: Icons.close, size: 16, lineWidth: 2.2, color: Palette.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .background(shape.fill(Palette.accent.opacity(0.07)))
        .overlay(shape.strokeBorder(Palette.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    private var parsed: ParsedPhrase {
        let key = Memo.Key(text: text, places: store.activePlaces.map(\.name), morning: store.settings.morning, evening: store.settings.evening, minute: Int(now.timeIntervalSince1970 / 60))
        if memo.key == key, let parsed = memo.parsed {
            return parsed
        }
        if memo.key?.minute != key.minute {
            memo.examples = [:]
        }
        let parsed = parser.parse(text)
        memo.key = key
        memo.parsed = parsed
        return parsed
    }

    private var allPieces: [PhrasePiece]? {
        guard keptWhole != text else { return nil }
        let key = Memo.Key(text: text, places: store.activePlaces.map(\.name), morning: store.settings.morning, evening: store.settings.evening, minute: Int(now.timeIntervalSince1970 / 60))
        if let cached = memo.pieces, cached.key == key {
            return cached.pieces
        }
        let pieces = parser.pieces(text)
        memo.pieces = (key, pieces)
        return pieces
    }

    // Each part of «завтра в 9 позвонить маме, в 12 обед с Ильёй» with its own time becomes its own reminder.
    private var multi: [(index: Int, piece: PhrasePiece)]? {
        guard let all = allPieces else { return nil }
        let gone = removed.text == text ? removed.indexes : []
        return all.enumerated().filter { !gone.contains($0.offset) }.map { (index: $0.offset, piece: $0.element) }
    }

    private var fieldHighlights: [Range<Int>] {
        allPieces.map { $0.flatMap(\.parsed.highlights) } ?? parsed.highlights
    }

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    private var reminder: Reminder {
        let result = parsed
        var reminder = Reminder(
            title: result.title,
            schedule: overrides.schedule ?? (flipped ? result.alternative : nil) ?? result.schedule,
            preAlerts: overrides.preAlerts ?? result.preAlerts,
            nag: result.nag,
            urgent: overrides.urgent ?? result.urgent,
            placeIDs: overrides.placeIDs ?? result.placeNames.compactMap { name in store.activePlaces.first { $0.name == name }?.id },
            placeTrigger: overrides.placeTrigger ?? result.placeTrigger ?? .arrive,
            sound: overrides.sound ?? .standard,
            items: listItems,
            createdAt: now
        )
        reminder.id = draft.id
        return reminder
    }

    // «Купить хлеб, молоко и яйца» fills the list by itself until the person touches it.
    private var listItems: [ChecklistItem] {
        if let items = overrides.items {
            return items
        }
        let title = parsed.title
        if let cached = memo.items, cached.title == title {
            return cached.items
        }
        let items = Checklist.isShopping(title) ? Checklist.items(in: title).map { ChecklistItem(text: $0) } : []
        memo.items = (title, items)
        return items
    }

    private var showsListOffer: Bool {
        !listDeclined && !parsed.title.isEmpty && (Checklist.isShopping(parsed.title) || !listItems.isEmpty)
    }

    private var listOffer: some View {
        let items = listItems
        let learned = Checklist.suggestions(for: items, in: store.reminders, excluding: draft.id)
        let taken = Set(items.map { Checklist.split($0.text).name.lowercased() })
        let hints = learned.isEmpty ? Array(ChecklistHints.staples.filter { !taken.contains($0.lowercased()) }.prefix(5)) : learned
        let previous = items.isEmpty ? Checklist.previous(for: parsed.title, in: store.reminders, excluding: draft.id) : nil
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Glyph(paths: Icons.list, size: 20, lineWidth: 2, color: Palette.accentText)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .circular).fill(Palette.accent.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Make a list?")
                            .font(.app(.golos, 16, weight: 600))
                        Text("You can tick items right in the shop.")
                            .font(.app(.golos, 14))
                            .foregroundStyle(Palette.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // «No» to the question: the reminder stays without a list.
                    Button {
                        Feedback.play(.select)
                        withAnimation(Motion.standard) {
                            overrides.items = []
                            listDeclined = true
                        }
                    } label: {
                        Glyph(paths: Icons.close, size: 14, lineWidth: 2, color: Palette.secondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(Text("Without a list"))
                }
                ChecklistRows(items: items, framed: false, onToggle: { item in
                    var updated = items
                    if let index = updated.firstIndex(where: { $0.id == item.id }) {
                        updated[index].done.toggle()
                    }
                    overrides.items = updated
                }, onAdd: { text in
                    overrides.items = items + [ChecklistItem(text: text)]
                }, onRemove: { item in
                    overrides.items = items.filter { $0.id != item.id }
                })
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .panel()
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .circular)
                    .strokeBorder(Palette.accent.opacity(0.45), lineWidth: 1.5)
            }
            if !hints.isEmpty, items.count < Reminder.maximumItems {
                ChecklistSuggestions(title: learned.isEmpty ? "Often bought" : "You often buy", names: hints) { name in
                    overrides.items = items + [ChecklistItem(text: name)]
                }
                .padding(.top, 12)
            }
            if let previous {
                Button {
                    Feedback.play(.select)
                    overrides.items = previous
                } label: {
                    Text(verbatim: String(localized: "Like last time · \(previous.count) items", bundle: .app, locale: .app))
                        .font(.app(.golos, 15, weight: 600))
                        .foregroundStyle(Palette.accentText)
                        .frame(height: 40)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(RowPressStyle())
                .padding(.top, 10)
            }
        }
    }

    // The other reading of a bare hour; the choice belongs to this exact text and goes away when it changes.
    private var flipped: Bool {
        flippedFor == text && parsed.alternative != nil
    }

    private var otherReading: Schedule? {
        guard overrides.schedule == nil, let alternative = parsed.alternative else { return nil }
        return flipped ? parsed.schedule : alternative
    }

    @ViewBuilder
    private var readingChip: some View {
        if let other = otherReading, let date = calendar.date(from: DateComponents(year: other.start.year, month: other.start.month, day: other.start.day, hour: other.time.hour, minute: other.time.minute)) {
            Button {
                flippedFor = flipped ? nil : text
                Feedback.play(.select)
            } label: {
                HStack(spacing: 6) {
                    Glyph(paths: Icons.clock, size: 15, lineWidth: 2, color: Palette.text)
                    Text(verbatim: String(localized: "or \(describer.dayAndTime(date, now: now))", bundle: .app, locale: .app).capitalizedFirst(locale))
                }
            }
            .buttonStyle(RaisedChipStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .transition(.opacity)
        }
    }

    private var when: Date? {
        guard let schedule = reminder.schedule else { return nil }
        return Recurrence.next(schedule, after: now.addingTimeInterval(-60), limit: 1, calendar: calendar).first
    }

    var body: some View {
        ZStack {
            PushStack(path: $path) {
                TimelineView(.everyMinute) { _ in
                    content
                }
            } destination: { route in
                switch route {
                case .repeating:
                    RepeatScreen(draft: draftBinding, now: now, calendar: calendar, locale: locale) { path.removeLast() }
                case .early:
                    EarlyScreen(draft: draftBinding, now: now, calendar: calendar, locale: locale) { path.removeLast() }
                case .sound:
                    SoundScreen(store: store, choice: soundBinding, locale: locale) { path.removeLast() }
                case .places:
                    PlacesScreen(store: store, title: parsed.title, placeIDs: placesBinding, trigger: triggerBinding, onNewPlace: { path.append(.newPlace) }, onBack: { path.removeLast() }, reminderID: draft.id)
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
            DateTimeScreen(initial: when ?? now.addingTimeInterval(3600), now: now, settings: store.settings, calendar: calendar, locale: locale, repeats: reminder.schedule?.rule != nil, onDone: { date in
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

    // The cross on the voice screen started from the plus closes everything; the keyboard button keeps the phrase screen.
    private func heard(_ spoken: String?) {
        let phrase = String((spoken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").prefix(Reminder.maximumTitleLength))
        if !phrase.isEmpty {
            text = phrase
            listening = false
        } else if text.isEmpty, startWithVoice, !VoiceRecognizer.blocked {
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
                    if let multi {
                        multiList(multi)
                            .padding(.top, 22)
                            .transition(.opacity)
                    } else {
                        single
                    }
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
                Text(verbatim: multi.map { String(localized: "Save \($0.count)", bundle: .app, locale: .app) } ?? (sharing && multi == nil ? String(localized: "Send to \(sharedWith.count)", bundle: .app, locale: .app) : confirmTitle))
                    .contentTransition(.numericText())
            }
            .disabled(multi.map(\.isEmpty) ?? parsed.title.isEmpty)
            if showsQuickTimes {
                quickTimes
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: showsQuickTimes)
        .animation(Motion.standard, value: multi?.map(\.index))
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardShown = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardShown = false }
        .animation(Motion.standard, value: when)
        .animation(Motion.standard, value: reminder.placeIDs)
        .animation(Motion.standard, value: overrides)
        .animation(Motion.standard, value: earlySuggestion)
    }

    @ViewBuilder
    private var single: some View {
        ReminderPreview(when: when, place: placeLine, summary: summaryLine, summaryLines: 2, describer: describer, calendar: calendar)
            .contentShape(Rectangle())
            .onTapGesture { pickingDate = true }
            .padding(.top, 12)
        readingChip
        if let shift = partShift {
            partShiftCard(shift)
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
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
        if showsListOffer {
            listOffer
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        addOns
            .padding(.top, 12)
        if sharing {
            sharingSection
                .padding(.top, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        suggestions
            .padding(.top, 14)
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
            Text("Rema splits the phrase at commas and conjunctions when each part has its own time. Remove extra ones with the cross.")
                .font(.app(.golos, 13))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
                .padding(.top, 10)
            Button {
                Feedback.play(.select)
                withAnimation(Motion.standard) { keptWhole = text }
            } label: {
                Text("Keep as one reminder")
                    .font(.app(.golos, 15, weight: 600))
                    .foregroundStyle(Palette.accentText)
                    .frame(height: 40)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(RowPressStyle())
            .padding(.top, 4)
        }
    }

    private func pieceRow(_ index: Int, _ piece: PhrasePiece) -> some View {
        let schedule = piece.parsed.schedule
        let date = schedule.flatMap { Recurrence.next($0, after: now.addingTimeInterval(-60), limit: 1, calendar: calendar).first }
        let line: String = {
            if let rule = schedule?.rule {
                return describer.repeatText(rule)
            }
            return date.map { describer.dayTitle($0).lowercased(with: locale) } ?? ""
        }()
        return HStack(spacing: 14) {
            Text(verbatim: date.map(describer.time) ?? "")
                .font(.app(.jost, 24, weight: 500))
                .monospacedDigit()
                .timeColumn(size: 24)
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
                Feedback.play(.select)
                withAnimation(Motion.standard) {
                    if removed.text != text {
                        removed = Removed(text: text)
                    }
                    removed.indexes.insert(index)
                    // With every part crossed out the phrase goes back to being one reminder.
                    if multi?.isEmpty == true {
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
        .frame(minHeight: 64)
    }

    private func pieceReminder(_ parsed: ParsedPhrase) -> Reminder {
        Reminder(
            title: parsed.title,
            schedule: parsed.schedule,
            preAlerts: parsed.preAlerts,
            nag: parsed.nag,
            urgent: parsed.urgent,
            placeIDs: parsed.placeNames.compactMap { name in store.activePlaces.first { $0.name == name }?.id },
            placeTrigger: parsed.placeTrigger ?? .arrive,
            items: Checklist.isShopping(parsed.title) ? Checklist.items(in: parsed.title).map { ChecklistItem(text: $0) } : [],
            createdAt: now
        )
    }

    private var earlySuggestion: EarlySuggestion? {
        guard !earlyDismissed, Remote.shared.isOn(.suggestions), let when else { return nil }
        return Suggestions.early(title: parsed.title, when: when, preAlerts: reminder.preAlerts, now: now)
    }

    private var input: some View {
        PhraseField(text: $text, highlights: fieldHighlights, focused: $focused, onSubmit: confirm)
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
                return String(localized: "or pick an option above the keyboard", bundle: .app, locale: .app)
            }
            return placeLine == nil ? String(localized: "for example, tomorrow at 9", bundle: .app, locale: .app) : title
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
            if Account.shared.isSignedIn {
                Chip(title: "With friends", selected: sharing, icon: sharing ? Icons.people : Icons.plus) {
                    Feedback.play(.toggle)
                    withAnimation(Motion.standard) { sharing.toggle() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // The friends who get the reminder and whether one «done» counts for everybody; the time is one moment for all.
    private var sharingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "With whom")
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            if friendsService.friends.isEmpty {
                Note("Invite a friend first: Settings, Shared reminders.")
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(friendsService.friends) { friend in
                        let chosen = sharedWith.contains(friend.id)
                        Chip(title: LocalizedStringKey(friendsService.name(of: friend.id, fallback: friend.name)), selected: chosen) {
                            Feedback.play(chosen ? .uncheck : .check)
                            if chosen {
                                sharedWith.removeAll { $0 == friend.id }
                            } else {
                                sharedWith.append(friend.id)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            PanelList {
                ToggleRow(icon: Icons.check, iconColor: Palette.text, title: "Each ticks it alone", subtitle: String(localized: "or one «done» for everybody", bundle: .app, locale: .app), isOn: Binding(get: { !oneDone }, set: { oneDone = !$0 }))
            }
            .padding(.top, 12)
            if let when {
                let city = TimeZone.current.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? TimeZone.current.identifier
                Note(verbatim: String(localized: "Everybody gets it at the same moment, \(describer.time(when)) by \(city) time. Only you can change it.", bundle: .app, locale: .app))
                    .padding(.top, 10)
            }
        }
    }

    private var exampleSamples: [String] {
        Remote.shared.exampleOverride ?? [
            String(localized: "in 2 hours", bundle: .app, locale: .app),
            String(localized: "on Friday evening", bundle: .app, locale: .app),
            String(localized: "every Tue and Thu at 8", bundle: .app, locale: .app),
            String(localized: "every year on October 12", bundle: .app, locale: .app),
            String(localized: "when I leave work", bundle: .app, locale: .app),
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
                            Text(verbatim: phrase.quoted())
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
                        Text(verbatim: sample.quoted())
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
        keyboardShown && multi == nil && !parsed.title.isEmpty && reminder.schedule == nil && reminder.placeIDs.isEmpty
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
            let name = result.placeNames.first ?? String(localized: "Work", bundle: .app, locale: .app)
            return String(localized: "by place · \(name)", bundle: .app, locale: .app)
        }
        guard let schedule = result.schedule,
              let date = Recurrence.next(schedule, after: now.addingTimeInterval(-60), limit: 1, calendar: calendar).first else { return "" }
        switch schedule.rule {
        case .weekly(let days):
            return "\(describer.weekdayList(days)) · \(describer.shortTime(date))"
        case .yearly:
            let day = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)).replacingOccurrences(of: ".", with: "")
            return String(localized: "yearly, \(day)", bundle: .app, locale: .app)
        default:
            if calendar.isDate(date, inSameDayAs: now) {
                return String(localized: "today, \(describer.shortTime(date))", bundle: .app, locale: .app)
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
            return String(localized: "Remind \(describer.dayAndTime(when, now: now))", bundle: .app, locale: .app)
        }
        if !reminder.placeIDs.isEmpty {
            return String(localized: "Remind by place", bundle: .app, locale: .app)
        }
        return String(localized: "Choose a time", bundle: .app, locale: .app)
    }

    private func confirm() {
        if let multi {
            guard !multi.isEmpty else { return }
            Feedback.play(.save)
            for entry in multi {
                store.save(pieceReminder(entry.piece.parsed))
            }
            RecentPhrases.remember(text)
            Notifier.shared.requestPermissionIfNeeded()
            onClose()
            return
        }
        guard !parsed.title.isEmpty else { return }
        guard when != nil || (!reminder.placeIDs.isEmpty && !sharing) else {
            pickingDate = true
            return
        }
        if sharing {
            guard !sharedWith.isEmpty else {
                Feedback.play(.error)
                return
            }
            Feedback.play(.save)
            let people = sharedWith.compactMap { id in friendsService.state.friends.first { $0.id == id } }.map { SharedPerson(id: $0.id, name: $0.name) }
            friendsService.create(reminder, with: people, doneMode: oneDone ? .one : .each)
            RecentPhrases.remember(text)
            Notifier.shared.requestPermissionIfNeeded()
            onClose()
            return
        }
        Feedback.play(.save)
        // Three moves in a row count; keeping the usual time once starts the count again.
        if let used = parsed.usedPart {
            let part: PartShift.Part? = used == store.settings.evening ? .evening : used == store.settings.morning ? .morning : nil
            if let part {
                if let chosen = overrides.schedule?.time, chosen != used {
                    PartShift.record(part, chosen)
                } else {
                    PartShift.reset(part)
                }
            }
        }
        store.save(reminder)
        RecentPhrases.remember(text)
        Notifier.shared.requestPermissionIfNeeded()
        onClose()
    }
}
