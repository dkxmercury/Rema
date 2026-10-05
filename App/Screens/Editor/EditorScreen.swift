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
    @FocusState private var titleFocused: Bool

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    private var when: Date {
        guard let schedule = draft.schedule else { return now }
        let components = DateComponents(year: schedule.start.year, month: schedule.start.month, day: schedule.start.day, hour: schedule.time.hour, minute: schedule.time.minute)
        let start = calendar.date(from: components) ?? now
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
                PlacesScreen(store: store, title: draft.title, placeIDs: $draft.placeIDs, trigger: $draft.placeTrigger, onNewPlace: { path.append(.newPlace) }, onBack: pop)
            case .newPlace:
                NewPlaceScreen(store: store, askToRemember: true, onSaved: { place in
                    draft.placeIDs.append(place.id)
                    pop()
                }, onBack: pop)
            }
        }
        .fullScreenCover(isPresented: $pickingDate) {
            DateTimeScreen(initial: when, now: now, settings: store.settings, calendar: calendar, locale: locale, onDone: { date in
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
        .confirmationDialog("Delete reminder?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Feedback.play(.delete)
                store.delete(draft.id)
                onClose()
            }
        }
        .onAppear {
            if isNew && draft.title.isEmpty {
                titleFocused = true
            }
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
        .modifier(Shake(amount: CGFloat(titleShake)))
        .animation(Motion.small, value: titleShake)
    }

    private var dateCard: some View {
        Button {
            pickingDate = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: describer.time(when))
                        .font(.app(.jost, 50, weight: 500))
                        .tracking(-0.5)
                        .frame(height: 54)
                        .contentTransition(.numericText())
                    Text(verbatim: describer.dayTitle(when))
                        .font(.app(.golos, 15, weight: 600))
                    Text(verbatim: describer.countdown(from: now, to: when))
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
                let parts = calendar.dateComponents([.hour, .minute], from: when)
                MiniDial(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
                    .animation(Motion.hand, value: when)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(verbatim: describer.fullDate(when)))
    }

    private var settingsPanel: some View {
        PanelList {
            NavigationRow(icon: Icons.repeatArrows, iconColor: Palette.yearly, title: "Repeat", action: { path.append(.repeating) }) {
                Text(verbatim: describer.repeatValue(draft.schedule))
                    .font(.app(.golos, 14))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .fixedSize()
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
            Hairline()
            NavigationRow(icon: Icons.pin, iconColor: Palette.text, title: "By place", action: { path.append(.places) }) {
                Text(verbatim: placeValue)
                    .font(.app(.golos, 14))
                    .foregroundStyle(Palette.secondary)
            }
            Hairline()
            ToggleRow(icon: Icons.bell, iconColor: Palette.text, title: "Persistent", subtitle: nagSubtitle, isOn: $draft.nag)
            Hairline()
            ToggleRow(icon: Icons.bolt, iconColor: Palette.urgentIcon, title: "Through Do Not Disturb", subtitle: String(localized: "marked Urgent"), isOn: $draft.urgent)
            Hairline()
            soundRow
        }
    }

    private var placeValue: String {
        let names = draft.placeIDs.compactMap { id in store.places.first { $0.id == id }?.name }
        return names.isEmpty ? String(localized: "No") : names.joined(separator: ", ")
    }

    private var nagSubtitle: String {
        let minutes = draft.nagInterval ?? store.settings.nagInterval
        return String(localized: "every \(minutes) minutes, until I mark it")
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
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        Feedback.play(.save)
        store.save(draft)
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
                    .lineLimit(1)
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
        .onChange(of: isOn) { _, _ in
            Feedback.play(.toggle)
        }
    }
}

struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Motion.press, value: configuration.isPressed)
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
