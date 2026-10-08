import RemaCore
import SwiftUI

struct EditingTarget: Identifiable {
    let id = UUID()
    let reminder: Reminder
    let isNew: Bool
}

struct ComposeTarget: Identifiable {
    let id = UUID()
    let voice: Bool
}

enum RootRoute: Hashable {
    case settings
    case defaultSound
    case places
    case place(UUID?)
    case account
    case deleteAccount
    case city
    case features
    case scheduled
}

// Lives outside the views, so the screen stack survives when a language change rebuilds them.
@MainActor
@Observable
final class RootNavigation {
    static let shared = RootNavigation()
    static let welcomeKey = "welcomeDone"
    static let introKey = "introDone"

    var path: [RootRoute] = []
    var languageCode = AppLanguage.current.rawValue
    var showingSignIn = !Account.shared.isSignedIn && !UserDefaults.standard.bool(forKey: RootNavigation.welcomeKey)
    var composeRequest: ComposeTarget?

    func requestCompose(voice: Bool) {
        composeRequest = ComposeTarget(voice: voice)
    }
}

struct LocalizedRoot<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var navigation = RootNavigation.shared

    var body: some View {
        let language = AppLanguage(rawValue: navigation.languageCode) ?? .english
        content()
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.layoutDirection)
            .id(navigation.languageCode)
    }
}

struct RootView: View {
    @State private var store = Store.shared
    @State private var navigation = RootNavigation.shared
    @State private var account = Account.shared
    @State private var sync = SyncService.shared
    @State private var remote = Remote.shared
    @State private var editing: EditingTarget?
    @State private var composing: ComposeTarget?
    @State private var showingCalendar = false
    @State private var showingLanguage = false
    @State private var showingIntro = false
    @State private var tips = TipCenter.shared
    @State private var dismissedHabits = Set(UserDefaults.standard.stringArray(forKey: "dismissedHabits") ?? [])
    @State private var announcement: RemoteConfig.Announcement?
    @Environment(\.openURL) private var openURL
    @Namespace private var zoom

    var body: some View {
        PushStack(path: $navigation.path) {
            home
        } destination: { route in
            destination(route)
        }
        .fullScreenCover(item: $editing) { target in
            EditorScreen(draft: target.reminder, isNew: target.isNew, store: store, onClose: { editing = nil })
        }
        .fullScreenCover(item: $composing) { target in
            PhraseScreen(store: store, startWithVoice: target.voice, onClose: { composing = nil })
        }
        .fullScreenCover(isPresented: $showingCalendar) {
            CalendarScreen(store: store, onClose: { showingCalendar = false })
                .zoomDestination("calendar", in: zoom)
        }
        .fullScreenCover(isPresented: $navigation.showingSignIn) {
            SignInFlow(onLanguage: { showingLanguage = true }, onFinish: finishSignIn)
                .fullScreenCover(isPresented: $showingLanguage) {
                    LanguageScreen(onClose: closeLanguage)
                }
        }
        .fullScreenCover(isPresented: Binding(get: { showingLanguage && !navigation.showingSignIn }, set: { showingLanguage = $0 })) {
            LanguageScreen(onClose: closeLanguage)
        }
        .fullScreenCover(isPresented: $showingIntro) {
            IntroScreen(store: store, onFinish: finishIntro, onFeatures: {
                finishIntro()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { navigation.path.append(.features) }
            })
        }
        .alert("Update Rema", isPresented: .constant(remote.needsUpdate && !navigation.showingSignIn)) {
            Button("Open App Store") { openURL(remote.link(.appStore)) }
        } message: {
            Text(verbatim: remote.text(remote.config.update) ?? String(localized: "This version is out of date. Install the new one from the App Store, it takes a minute.", bundle: .app, locale: .app))
        }
        .alert(
            Text(verbatim: announcement.flatMap { remote.text($0.title) } ?? "Rema"),
            isPresented: Binding(get: { announcement != nil }, set: { if !$0 { dismissAnnouncement() } })
        ) {
            if let link = announcement?.link.flatMap(URL.init(string:)) {
                Button("Open") {
                    openURL(link)
                    dismissAnnouncement()
                }
            }
            Button("OK", role: .cancel) { dismissAnnouncement() }
        } message: {
            Text(verbatim: announcement.flatMap { remote.text($0.text) } ?? "")
        }
        .onChange(of: remote.config) { _, _ in showAnnouncementIfNew() }
        .onChange(of: navigation.composeRequest?.id) { _, _ in openRequestedCompose() }
        .onChange(of: account.isSignedIn) { _, signedIn in
            // A session that ran out leaves no account to show, so its screens close.
            if !signedIn {
                navigation.path.removeAll { $0 == .account || $0 == .deleteAccount }
            }
        }
        .onAppear {
            showAnnouncementIfNew()
            showIntroIfNeeded()
            openRequestedCompose()
        }
        .preferredColorScheme(colorScheme)
    }

    @ViewBuilder
    private func destination(_ route: RootRoute) -> some View {
        switch route {
        case .settings:
            SettingsScreen(
                store: store,
                account: accountSummary,
                onSound: { navigation.path.append(.defaultSound) },
                onPlaces: { navigation.path.append(.places) },
                onSignIn: { navigation.showingSignIn = true },
                onAccount: { navigation.path.append(.account) },
                onLanguage: { showingLanguage = true },
                onCity: { navigation.path.append(.city) },
                onFeatures: { navigation.path.append(.features) },
                onBack: { navigation.path.removeLast() }
            )
        case .defaultSound:
            SoundScreen(store: store, choice: defaultSound) { navigation.path.removeLast() }
        case .places:
            PlacesListScreen(store: store, onOpen: { navigation.path.append(.place($0.id)) }, onAdd: { navigation.path.append(.place(nil)) }, onBack: { navigation.path.removeLast() })
        case .place(let id):
            NewPlaceScreen(store: store, existing: store.places.first { $0.id == id }, onSaved: { _ in navigation.path.removeLast() }, onBack: { navigation.path.removeLast() })
        case .city:
            CityScreen { navigation.path.removeLast() }
        case .features:
            FeaturesScreen(onPlaces: { navigation.path.append(.places) }, onBack: { navigation.path.removeLast() })
        case .scheduled:
            ScheduledScreen(
                content: ScheduledContent.make(reminders: store.reminders, places: store.places, now: Date(), calendar: .current, locale: AppLanguage.current.locale, withPlaces: remote.isOn(.places)),
                onOpen: open,
                onBack: { navigation.path.removeLast() },
                loading: sync.loadingFirstTime
            )
        case .account:
            if let summary = accountSummary {
                AccountScreen(
                    summary: summary,
                    onSignOut: { discarding in
                        let done = await SyncService.shared.signOut(discardingChanges: discarding)
                        if done {
                            navigation.path.removeAll { $0 == .account }
                        }
                        return done
                    },
                    onDelete: { navigation.path.append(.deleteAccount) },
                    onBack: { navigation.path.removeLast() }
                )
            } else {
                Color.clear
            }
        case .deleteAccount:
            DeleteAccountScreen(
                onDeleted: { navigation.path.removeAll { $0 == .account || $0 == .deleteAccount } },
                onBack: { navigation.path.removeLast() }
            )
        }
    }

    private var accountSummary: AccountScreen.Summary? {
        guard let session = account.session else { return nil }
        return AccountScreen.Summary(
            email: account.visibleEmail,
            method: session.method,
            status: sync.status,
            savedAt: sync.savedAt,
            reminders: store.activeReminders.count,
            places: store.activePlaces.count,
            refused: sync.hasRefusedChanges
        )
    }

    private func finishSignIn(_ signedIn: Bool) {
        UserDefaults.standard.set(true, forKey: RootNavigation.welcomeKey)
        navigation.showingSignIn = false
        if signedIn {
            SyncService.shared.becameActive()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showIntroIfNeeded() }
    }

    private func showIntroIfNeeded() {
        guard !navigation.showingSignIn, !UserDefaults.standard.bool(forKey: RootNavigation.introKey) else { return }
        showingIntro = true
    }

    private func finishIntro() {
        UserDefaults.standard.set(true, forKey: RootNavigation.introKey)
        showingIntro = false
    }

    private func closeLanguage() {
        showingLanguage = false
        guard navigation.languageCode != AppLanguage.current.rawValue else { return }
        Notifier.shared.configure()
        Notifier.shared.scheduleSoon()
        Task { await Account.shared.updateLanguage() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            navigation.languageCode = AppLanguage.current.rawValue
        }
    }

    // A control or the Action button can open the app while another screen is up; that one closes first.
    private func openRequestedCompose() {
        guard let request = navigation.composeRequest else { return }
        navigation.composeRequest = nil
        guard !navigation.showingSignIn, !showingIntro else { return }
        let root = UIApplication.shared.mainWindow?.rootViewController
        if editing != nil || showingCalendar || composing != nil || showingLanguage || root?.presentedViewController != nil {
            editing = nil
            showingCalendar = false
            composing = nil
            showingLanguage = false
            root?.dismiss(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { composing = request }
        } else {
            composing = request
        }
    }

    private func showAnnouncementIfNew() {
        guard announcement == nil, let next = remote.activeAnnouncement,
              UserDefaults.standard.string(forKey: "announcementSeen") != next.id else { return }
        announcement = next
    }

    private func dismissAnnouncement() {
        if let id = announcement?.id {
            UserDefaults.standard.set(id, forKey: "announcementSeen")
        }
        announcement = nil
    }

    private var defaultSound: Binding<SoundChoice> {
        Binding(
            get: { store.settings.defaultSound },
            set: { value in store.update { $0.defaultSound = value } }
        )
    }

    private var colorScheme: ColorScheme? {
        switch store.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var home: some View {
        TimelineView(.everyMinute) { timeline in
            HomeScreen(
                content: HomeContent.make(
                    reminders: store.reminders,
                    places: store.places,
                    now: timeline.date,
                    calendar: .current,
                    locale: AppLanguage.current.locale,
                    missed: Notifier.missedEnabled
                ),
                onToggle: toggle,
                onOpen: open,
                onCompose: { composing = ComposeTarget(voice: false) },
                onVoice: {
                    Feedback.play(.select)
                    composing = ComposeTarget(voice: VoiceRecognizer.available)
                },
                onCalendar: { showingCalendar = true },
                onSettings: { navigation.path.append(.settings) },
                scheduledCount: ScheduledContent.count(reminders: store.reminders, now: timeline.date, calendar: .current, withPlaces: remote.isOn(.places)),
                onScheduled: { navigation.path.append(.scheduled) },
                zoom: zoom,
                onDelete: { id in
                    guard let copy = store.reminder(id) else { return nil }
                    let places = store.releasedPlaces(of: id)
                    withAnimation(Motion.standard) { store.delete(id) }
                    return { withAnimation(Motion.standard) { store.restore(copy, places: places) } }
                },
                onMove: move,
                habit: remote.isOn(.suggestions) ? Suggestions.habit(in: store.reminders, now: timeline.date, calendar: .current, dismissed: dismissedHabits) : nil,
                onHabit: answerHabit,
                onPostpone: postpone,
                tip: tips.next(store: store, now: timeline.date),
                onTip: answerTip,
                loadingAccount: sync.loadingFirstTime
            )
        }
    }

    private func postpone(_ row: HomeContent.Row, _ choice: HomeScreen.Postpone) {
        let calendar = Calendar.current
        let now = Date()
        let date: Date
        switch choice {
        case .hour:
            let later = now.addingTimeInterval(3600)
            date = calendar.dateInterval(of: .minute, for: later)?.start ?? later
        case .morning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            let morning = store.settings.morning
            date = calendar.date(bySettingHour: morning.hour, minute: morning.minute, second: 0, of: tomorrow) ?? tomorrow
        case .custom:
            open(row.reminderID)
            return
        }
        guard let reminder = store.reminder(row.reminderID) else { return }
        if reminder.schedule?.rule == nil {
            _ = move(row.reminderID, to: date)
        } else {
            withAnimation(Motion.standard) { store.snooze(row.reminderID, until: date) }
        }
        Feedback.play(.save)
    }

    private func answerTip(_ tip: Tip, accepted: Bool) {
        tips.dismiss(tip)
        if tip == .weather, accepted {
            Task { await WeatherAdvisor.shared.setEnabled(true) }
        }
    }

    private func answerHabit(_ suggestion: HabitSuggestion, accepted: Bool) {
        if accepted, var reminder = store.reminder(suggestion.reminderID), var schedule = reminder.schedule {
            schedule.rule = .weekly([suggestion.weekday])
            reminder.schedule = schedule
            store.save(reminder)
            Feedback.play(.save)
        }
        dismissedHabits.insert(suggestion.key)
        UserDefaults.standard.set(Array(dismissedHabits), forKey: "dismissedHabits")
    }

    private func move(_ id: UUID, to date: Date) -> (() -> Void)? {
        guard let original = store.reminder(id), original.schedule?.rule == nil else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        var moved = original
        moved.schedule = Schedule(start: LocalDate(date, in: .current), time: LocalTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0))
        moved.snoozedUntil = nil
        withAnimation(Motion.standard) { store.save(moved) }
        return {
            guard var current = store.reminder(id) else { return }
            current.schedule = original.schedule
            current.snoozedUntil = original.snoozedUntil
            withAnimation(Motion.standard) { store.save(current) }
        }
    }

    private func toggle(_ row: HomeContent.Row) {
        Feedback.play(row.done ? .uncheck : .check)
        withAnimation(Motion.standard) {
            if row.done {
                store.reopen(row.reminderID, before: row.occurrence)
            } else {
                store.complete(row.reminderID, through: row.occurrence)
            }
        }
    }

    private func open(_ id: UUID) {
        guard let reminder = store.reminder(id) else { return }
        editing = EditingTarget(reminder: reminder, isNew: false)
    }
}
