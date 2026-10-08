import RemaCore
import SwiftUI

enum EditorRoute: Hashable {
    case repeating
    case early
    case sound
    case places
    case newPlace
}

struct EditorScreen: View {
    @State var draft: Reminder
    let isNew: Bool
    let store: Store
    var now: Date = Date()
    var calendar: Calendar = .current
    var locale: Locale = AppLanguage.current.locale
    let onClose: () -> Void

    @State private var path: [EditorRoute] = []
    @State private var pickingDate = false
    @State private var confirmingDelete = false
    @State private var titleShake = 0
    @State private var showsList = false
    @State private var foundContact: ContactLink?
    @State private var contactDismissed = false
    @State private var opened: Reminder?
    @FocusState private var titleFocused: Bool

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    // A shared reminder keeps the time in the zone of the one who made it; here it is shown in the zone of this phone.
    private var when: Date {
        guard let schedule = draft.schedule else { return now }
        var zoned = calendar
        if let zone = schedule.timeZone.flatMap(TimeZone.init(identifier:)) {
            zoned.timeZone = zone
        }
        let components = DateComponents(year: schedule.start.year, month: schedule.start.month, day: schedule.start.day, hour: schedule.time.hour, minute: schedule.time.minute)
        let start = zoned.date(from: components) ?? now
        if schedule.rule == nil {
            return start
        }
        return Recurrence.next(schedule, after: now, limit: 1, calendar: calendar).first ?? start
    }

    var body: some View {
        PushStack(path: $path) {
            content
        } destination: { route in
            switch route {
            case .repeating:
                RepeatScreen(draft: $draft, now: now, calendar: calendar, locale: locale) { pop() }
            case .early:
                EarlyScreen(draft: $draft, now: now, calendar: calendar, locale: locale) { pop() }
            case .sound:
                SoundScreen(store: store, choice: $draft.sound, locale: locale) { pop() }
            case .places:
                PlacesScreen(store: store, title: draft.title, placeIDs: $draft.placeIDs, trigger: $draft.placeTrigger, onNewPlace: { path.append(.newPlace) }, onBack: pop, reminderID: draft.id)
            case .newPlace:
                NewPlaceScreen(store: store, askToRemember: true, onSaved: { place in
                    draft.placeIDs.append(place.id)
                    pop()
                }, onBack: pop)
            }
        }
        .fullScreenCover(isPresented: $pickingDate) {
            DateTimeScreen(initial: when, now: now, settings: store.settings, calendar: calendar, locale: locale, repeats: draft.schedule?.rule != nil, onDone: { date in
                setDate(date)
                pickingDate = false
            }, onClose: { pickingDate = false })
        }
    }

    private var content: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    titleField
                        .padding(.top, 16)
                    dateCard
                        .padding(.top, 14)
                    if let contact = shownContact {
                        contactCard(contact)
                            .padding(.top, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if showsListSection {
                        listSection
                            .padding(.top, 20)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    settingsPanel
                        .padding(.top, 12)
                    if !isNew {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Text("Delete reminder")
                                .font(.app(.golos, 15, weight: 600))
                                .foregroundStyle(Palette.urgentText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(PressableStyle())
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .pinnedHeader {
                ScreenHeader(title: "Reminder", leading: .close, action: onClose)
            }
            PrimaryBar(action: save) {
                Text("Save")
            }
        }
        .foregroundStyle(Palette.text)
        .confirmationDialog(draft.shared == nil ? Text("Delete reminder?") : Text("Delete the reminder for everyone in it?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Feedback.play(.delete)
                store.delete(draft.id)
                onClose()
            }
        }
        .onAppear {
            if opened == nil {
                opened = draft
                contactDismissed = ContactsFeed.isDismissed(draft.id)
            }
            if isNew && draft.title.isEmpty {
                titleFocused = true
            }
        }
        .task(id: draft.title) {
            guard draft.contact == nil, !contactDismissed, ContactsFeed.authorized, !draft.title.isEmpty else {
                foundContact = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let title = draft.title
            let found = await Task.detached { ContactsFeed.match(title) }.value
            guard !Task.isCancelled else { return }
            withAnimation(Motion.standard) { foundContact = found }
        }
    }

    private var titleField: some View {
        TextField(text: $draft.title, prompt: Text("What to remind about").foregroundColor(Palette.secondary)) {
            Text("Reminder text")
        }
        .font(.app(.golos, 28, weight: 600))
        .tint(Palette.accent)
        .focused($titleFocused)
        .frame(height: 44)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.text).frame(height: 2)
        }
        .overlay(alignment: .bottomTrailing) {
            if draft.title.count >= Reminder.maximumTitleLength - 40 {
                Text(verbatim: "\(draft.title.count)/\(Reminder.maximumTitleLength)")
                    .font(.app(.golos, 12, weight: 500))
                    .monospacedDigit()
                    .foregroundStyle(draft.title.count >= Reminder.maximumTitleLength ? Palette.accentText : Palette.secondary)
                    .padding(.bottom, 12)
            }
        }
        .onChange(of: draft.title) { _, title in
            if title.count > Reminder.maximumTitleLength {
                draft.title = String(title.prefix(Reminder.maximumTitleLength))
            }
        }
        .modifier(Shake(amount: CGFloat(titleShake)))
        .animation(Motion.small, value: titleShake)
    }

    private var dateCard: some View {
        Button {
            pickingDate = true
        } label: {
            Group {
                if draft.schedule == nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add a time")
                            .font(.app(.golos, 20, weight: 600))
                        if !draft.placeIDs.isEmpty {
                            Text(verbatim: describer.placeText(draft, places: store.places))
                                .font(.app(.golos, 13))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: describer.time(when))
                                .font(.app(.jost, 50, weight: 500))
                                .tracking(-0.5)
                                .frame(height: 54)
                                .contentTransition(.numericText())
                            Text(verbatim: describer.dayTitle(when))
                                .font(.app(.golos, 15, weight: 600))
                            Text(verbatim: draft.schedule?.rule == nil && when < now ? String(localized: "This time has already passed", bundle: .app, locale: .app) : describer.countdown(from: now, to: when))
                                .font(.app(.golos, 13))
                                .foregroundStyle(draft.schedule?.rule == nil && when < now ? Palette.urgentText : Palette.secondary)
                        }
                        Spacer(minLength: 0)
                        let parts = calendar.dateComponents([.hour, .minute], from: when)
                        MiniDial(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
                            .animation(Motion.hand, value: when)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(draft.schedule == nil ? Text("Add a time") : Text(verbatim: describer.fullDate(when)))
    }

    private var settingsPanel: some View {
        PanelList {
            NavigationRow(icon: Icons.repeatArrows, iconColor: Palette.yearly, title: "Repeat", action: { path.append(.repeating) }) {
                Text(verbatim: describer.repeatValue(draft.schedule))
                    .font(.app(.golos, 14))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Hairline()
            NavigationRow(icon: Icons.early, iconColor: Palette.text, title: "In advance", action: { path.append(.early) }) {
                if draft.preAlerts.isEmpty {
                    Text("No")
                        .font(.app(.golos, 14))
                        .foregroundStyle(Palette.secondary)
                } else {
                    HStack(spacing: 6) {
                        ForEach(draft.preAlerts.sorted(by: >), id: \.self) { minutes in
                            Tag(text: describer.leadText(minutes))
                        }
                    }
                    .fixedSize()
                }
            }
            if !showsListSection {
                Hairline()
                NavigationRow(icon: Icons.list, iconColor: Palette.text, title: "List", action: {
                    withAnimation(Motion.standard) { showsList = true }
                }) {
                    Text("No")
                        .font(.app(.golos, 14))
                        .foregroundStyle(Palette.secondary)
                }
            }
            if Remote.shared.isOn(.places) || !draft.placeIDs.isEmpty {
                Hairline()
                NavigationRow(icon: Icons.pin, iconColor: Palette.text, title: "By place", action: { path.append(.places) }) {
                    Text(verbatim: placeValue)
                        .font(.app(.golos, 14))
                        .foregroundStyle(Palette.secondary)
                }
            }
            Hairline()
            ToggleRow(icon: Icons.bell, iconColor: Palette.text, title: "Persistent", subtitle: nagSubtitle, isOn: $draft.nag)
            Hairline()
            ToggleRow(icon: Icons.bolt, iconColor: Palette.urgentIcon, title: "Through Do Not Disturb", subtitle: String(localized: "marked Urgent", bundle: .app, locale: .app), isOn: $draft.urgent)
            Hairline()
            soundRow
        }
    }

    private var shownContact: ContactLink? {
        draft.contact ?? (contactDismissed ? nil : foundContact)
    }

    // The person the reminder is about, offered from the contacts; only «Add» gives the notification a «Call» button.
    private func contactCard(_ link: ContactLink) -> some View {
        let attached = draft.contact != nil
        // The isolate keeps the digits of a number in order inside an Arabic line.
        let phone = "\u{2066}\(link.phone)\u{2069}"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(verbatim: String(link.name.prefix(1)).uppercased())
                    .font(.app(.golos, 18, weight: 600))
                    .foregroundStyle(Palette.accentText)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Palette.accent.opacity(0.16)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: link.name)
                        .font(.app(.golos, 16, weight: 600))
                        .lineLimit(1)
                    Text(verbatim: String(localized: "\(phone) · from contacts", bundle: .app, locale: .app))
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !attached {
                    Button {
                        Feedback.play(.select)
                        withAnimation(Motion.standard) {
                            draft.contact = link
                            foundContact = nil
                        }
                    } label: {
                        Text("Add")
                            .font(.app(.golos, 15, weight: 600))
                            .foregroundStyle(Palette.accentText)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(RowPressStyle())
                }
                Button {
                    Feedback.play(.select)
                    withAnimation(Motion.standard) {
                        contactDismissed = true
                        draft.contact = nil
                        foundContact = nil
                    }
                    ContactsFeed.dismiss(draft.id)
                } label: {
                    Glyph(paths: Icons.close, size: 14, lineWidth: 2, color: Palette.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressableStyle())
                .padding(.trailing, -12)
                .accessibilityLabel(Text("Remove contact"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .panel()
            Text(verbatim: attached ? String(localized: "Rema found \(link.name) in your contacts. The notification will have a Call button.", bundle: .app, locale: .app) : String(localized: "Rema found \(link.name) in your contacts. Add a Call button to the notification?", bundle: .app, locale: .app))
                .font(.app(.golos, 13))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        }
    }

    // A shopping title opens the list by itself, anything else gets it from the row below.
    private var showsListSection: Bool {
        showsList || !draft.items.isEmpty || Checklist.isShopping(draft.title)
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(verbatim: draft.items.isEmpty ? String(localized: "List", bundle: .app, locale: .app) : "\(String(localized: "List", bundle: .app, locale: .app)) · \(ChecklistHints.progress(draft))")
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            ChecklistRows(items: draft.items, focusOnAppear: showsList && draft.items.isEmpty, onToggle: { item in
                if let index = draft.items.firstIndex(where: { $0.id == item.id }) {
                    draft.items[index].done.toggle()
                }
            }, onAdd: { text in
                draft.items.append(ChecklistItem(text: text))
            }, onRemove: { item in
                draft.items.removeAll { $0.id == item.id }
            })
            let hints = listHints
            if !hints.isEmpty {
                ChecklistSuggestions(title: "Often together with this", names: hints) { name in
                    draft.items.append(ChecklistItem(text: name))
                }
                .padding(.top, 12)
            }
            if !draft.items.isEmpty {
                PanelList {
                    ToggleRow(icon: Icons.check, iconColor: Palette.text, title: "Done when all ticked", subtitle: String(localized: "the reminder marks itself", bundle: .app, locale: .app), isOn: $draft.doneWhenChecked)
                }
                .padding(.top, 12)
            }
        }
        .animation(Motion.standard, value: draft.items)
    }

    private var listHints: [String] {
        guard draft.items.count < Reminder.maximumItems else { return [] }
        let learned = Checklist.suggestions(for: draft.items, in: store.reminders, excluding: draft.id, limit: 3)
        guard learned.isEmpty, Checklist.isShopping(draft.title) else { return learned }
        let taken = Set(draft.items.map { Checklist.split($0.text).name.lowercased() })
        return Array(ChecklistHints.staples.filter { !taken.contains($0.lowercased()) }.prefix(3))
    }

    private var placeValue: String {
        let names = draft.placeIDs.compactMap { id in store.places.first { $0.id == id }?.name }
        return names.isEmpty ? String(localized: "No", bundle: .app, locale: .app) : names.joined(separator: ", ")
    }

    private var nagSubtitle: String {
        let minutes = draft.nagInterval ?? store.settings.nagInterval
        if minutes == 1 {
            return String(localized: "every minute, until I mark it", bundle: .app, locale: .app)
        }
        return String(localized: "every \(minutes) minutes, until I mark it", bundle: .app, locale: .app)
    }

    private var soundRow: some View {
        HStack(spacing: 12) {
            Glyph(paths: Icons.note, size: 20, lineWidth: 2, color: Palette.text)
            Button {
                path.append(.sound)
            } label: {
                HStack(spacing: 12) {
                    Text("Sound")
                        .font(.app(.golos, 16, weight: 500))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: describer.soundName(draft.sound, settings: store.settings, sounds: store.sounds))
                        .font(.app(.golos, 14))
                        .foregroundStyle(Palette.secondary)
                }
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                SoundPlayer.preview(draft.sound, settings: store.settings, sounds: store.sounds)
            } label: {
                ZStack {
                    RaisedCircle(size: 30)
                    Glyph(paths: Icons.play, size: 12, color: Palette.text, filled: true)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(PressableStyle())
            .padding(.trailing, -8)
            .accessibilityLabel(Text("Play sound"))
        }
        .frame(minHeight: 52)
    }

    private func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    private func setDate(_ date: Date) {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let start = LocalDate(year: parts.year ?? 2026, month: parts.month ?? 1, day: parts.day ?? 1)
        let time = LocalTime(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
        withAnimation(Motion.standard) {
            var schedule = draft.schedule ?? Schedule(start: start, time: time)
            schedule.start = start
            schedule.time = time
            if case .yearly = schedule.rule {
                schedule.rule = .yearly(month: start.month, day: start.day)
            }
            if case .monthlyOnDay = schedule.rule {
                schedule.rule = .monthlyOnDay(start.day)
            }
            // The time was read on this phone, so for the friends it is the time of this phone's zone now.
            if draft.shared != nil {
                schedule.timeZone = calendar.timeZone.identifier
            }
            draft.schedule = schedule
            draft.completedThrough = nil
            draft.snoozedUntil = nil
        }
    }

    private func save() {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            titleShake += 1
            titleFocused = true
            Feedback.play(.error)
            return
        }
        // Without a time and a place the reminder would never come and would show up nowhere.
        guard draft.schedule != nil || !draft.placeIDs.isEmpty else {
            Feedback.play(.error)
            pickingDate = true
            return
        }
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        Feedback.play(.save)
        store.reloadIfChanged(edit: false)
        var reminder = draft
        // A notification, the widget or another phone may have marked it done or snoozed it while the editor was open.
        let before = store.reminder(draft.id)
        if let current = before, current.schedule == draft.schedule {
            reminder.completedThrough = current.completedThrough
            reminder.snoozedUntil = current.snoozedUntil
            reminder.history = current.history
            // Ticks given elsewhere while the editor was open stay, unless they were changed here.
            let openedTicks = Dictionary((opened?.items ?? []).map { ($0.id, $0.done) }, uniquingKeysWith: { first, _ in first })
            let latestTicks = Dictionary(current.items.map { ($0.id, $0.done) }, uniquingKeysWith: { first, _ in first })
            for index in reminder.items.indices {
                let item = reminder.items[index]
                if openedTicks[item.id] == item.done, let latest = latestTicks[item.id] {
                    reminder.items[index].done = latest
                }
            }
        }
        store.save(reminder)
        let occurrence = Agenda.listOccurrence(reminder, now: Date(), calendar: calendar)
        let finished = reminder.doneWhenChecked && !reminder.items.isEmpty && reminder.items.allSatisfy(\.done)
        if finished, !reminder.isDone(occurrence), before.map({ $0.items.isEmpty || !$0.items.allSatisfy(\.done) }) ?? true {
            store.complete(reminder.id, through: occurrence)
        }
        Notifier.shared.requestPermissionIfNeeded()
        onClose()
    }
}

struct NavigationRow<Value: View>: View {
    let icon: [String]
    let iconColor: Color
    let title: LocalizedStringKey
    var minHeight: CGFloat = 51
    let action: () -> Void
    @ViewBuilder var value: () -> Value

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Glyph(paths: icon, size: 20, lineWidth: 2, color: iconColor)
                Text(title)
                    .font(.app(.golos, 16, weight: 500))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                value()
                    .layoutPriority(1)
                Glyph(paths: Icons.chevron, size: 16, lineWidth: 2, color: Palette.secondary)
            }
            .frame(minHeight: minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}

struct ToggleRow: View {
    let icon: [String]
    let iconColor: Color
    let title: LocalizedStringKey
    let subtitle: String
    @Binding var isOn: Bool
    var minHeight: CGFloat = 60

    var body: some View {
        HStack(spacing: 12) {
            Glyph(paths: icon, size: 20, lineWidth: 2, color: iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(.golos, 16, weight: 500))
                Text(verbatim: subtitle)
                    .font(.app(.golos, 12))
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            LeverToggle(isOn: $isOn)
        }
        .frame(minHeight: minHeight)
        // VoiceOver reads the title and the state as one switch instead of a nameless one.
        .accessibilityElement(children: .combine)
        .onChange(of: isOn) { _, _ in
            Feedback.play(.toggle)
        }
    }
}

struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 4), y: 0))
    }
}
