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
    case snooze
    case birthdays
    case importReminders
    case friends
    case friend(String)
}

struct SharedTarget: Identifiable {
    let id: UUID
}

// Lives outside the views, so the screen stack survives when a language change rebuilds them.
@MainActor
@Observable
final class RootNavigation {
    static let shared = RootNavigation()
    // A friend's invitation that waits for the person to sign in.
    var pendingInvite: String?
    static let welcomeKey = "welcomeDone"
    static let introKey = "introDone"

    var path: [RootRoute] = []
    var languageCode = AppLanguage.current.rawValue
    var showingSignIn = !Account.shared.isSignedIn && !UserDefaults.standard.bool(forKey: RootNavigation.welcomeKey)
    var composeRequest: ComposeTarget?
    var openRequest: UUID?
    var editingOpen = false

    func requestCompose(voice: Bool) {
        composeRequest = ComposeTarget(voice: voice)
    }
}

struct LocalizedRoot<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var navigation = RootNavigation.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var appliedSize: DynamicTypeSize?

    // The fonts read the size once per build, so a new text size in iOS rebuilds the screens like a new language does.
    // While a reminder, a list or a phrase is open the rebuild waits, it would throw away what was typed.
    var body: some View {
        let language = AppLanguage(rawValue: navigation.languageCode) ?? .english
        let size = navigation.editingOpen ? appliedSize ?? typeSize : typeSize
        let _ = AppFonts.apply(size)
        content()
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.layoutDirection)
            .id("\(navigation.languageCode)-\(size)")
            .onChange(of: size, initial: true) { _, new in
                appliedSize = new
            }
    }
}

struct RootView: View {
    @State private var store = Store.shared
    @State private var navigation = RootNavigation.shared
    @State private var account = Account.shared
    @State private var sync = SyncService.shared
    @State private var remote = Remote.shared
    @State private var calendarFeed = CalendarFeed.shared
    @State private var editing: EditingTarget?
    @State private var checking: ChecklistTarget?
    @State private var composing: ComposeTarget?
    @State private var showingCalendar = false
    @State private var showingLanguage = false
    @State private var showingIntro = false
    @State private var tips = TipCenter.shared
    @State private var dismissedHabits = Set(UserDefaults.standard.stringArray(forKey: "dismissedHabits") ?? [])
    @State private var announcement: RemoteConfig.Announcement?
    @State private var inviting = false
    @State private var answering: InviteTarget?
    @State private var viewingShared: SharedTarget?
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
        .sheet(item: $checking) { target in
            ChecklistSheet(store: store, reminderID: target.id, onEdit: {
                checking = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { edit(target.id) }
            }, onClose: { checking = nil })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
            .presentationBackground(Palette.background)
        }
        .fullScreenCover(item: $composing) { target in
            PhraseScreen(store: store, startWithVoice: target.voice, onClose: { composing = nil })
        }
        .fullScreenCover(isPresented: $inviting) {
            InviteScreen(onClose: { inviting = false })
        }
        .sheet(item: $answering) { target in
            InviteAnswerSheet(code: target.code, onSignIn: {
                // The invitation opens again once the person has signed in.
                navigation.pendingInvite = target.code
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { navigation.showingSignIn = true }
            }, onClose: { answering = nil })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(Palette.background)
        }
        .sheet(item: $viewingShared) { target in
            SharedDetailScreen(store: store, reminderID: target.id, onEdit: {
                viewingShared = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { edit(target.id) }
            }, onClose: { viewingShared = nil })
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
            .presentationBackground(Palette.background)
        }
        .onOpenURL { url in openInvite(url) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in openInvite(activity.webpageURL) }
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
            if let link = announcement?.link.flatMap(URL.init(string:)), link.scheme == "https", link.host() != nil {
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
        .onChange(of: editing != nil || checking != nil || composing != nil || inviting) { _, open in navigation.editingOpen = open }
        .onChange(of: navigation.openRequest) { _, _ in openRequestedReminder() }
        .onChange(of: account.isSignedIn) { _, signedIn in
            // Someone new first sees the intro; the invitation opens when it closes.
            if signedIn, UserDefaults.standard.bool(forKey: RootNavigation.introKey), let code = navigation.pendingInvite {
                navigation.pendingInvite = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { answering = InviteTarget(code: code) }
            }
            // A session that ran out leaves no account to show, so its screens close.
            if !signedIn {
                navigation.path.removeAll { $0 == .account || $0 == .deleteAccount }
            }
        }
        .onAppear {
            showAnnouncementIfNew()
            showIntroIfNeeded()
            openRequestedCompose()
            openRequestedReminder()
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
                onSnooze: { navigation.path.append(.snooze) },
                onBirthdays: { navigation.path.append(.birthdays) },
                onImport: { navigation.path.append(.importReminders) },
                onFriends: { navigation.path.append(.friends) },
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
        case .snooze:
            SnoozeScreen(store: store) { navigation.path.removeLast() }
        case .birthdays:
            BirthdaysScreen(store: store) { navigation.path.removeLast() }
        case .importReminders:
            ImportScreen(store: store) { navigation.path.removeLast() }
        case .friends:
            FriendsScreen(
                store: store,
                onFriend: { navigation.path.append(.friend($0)) },
                onInvite: { inviting = true },
                onCode: { answering = InviteTarget(code: $0) },
                onSignIn: { navigation.showingSignIn = true },
                onBack: { navigation.path.removeLast() }
            )
        case .friend(let id):
            FriendScreen(store: store, friendID: id, onOpen: { viewingShared = SharedTarget(id: $0) }, onBack: { navigation.path.removeLast() })
        case .features:
            FeaturesScreen(
                onPlaces: { navigation.path.append(.places) },
                onFriends: { navigation.path.append(.friends) },
                onBirthdays: { navigation.path.append(.birthdays) },
                onBack: { navigation.path.removeLast() }
            )
        case .scheduled:
            ScheduledScreen(
                content: ScheduledContent.make(reminders: store.reminders, places: store.places, now: Date(), calendar: .current, locale: AppLanguage.current.locale, withPlaces: remote.isOn(.places), events: calendarFeed.entries(from: Date(), to: Date().addingTimeInterval(14 * 86_400))),
                done: DoneContent.make(reminders: store.reminders, now: Date(), calendar: .current, locale: AppLanguage.current.locale),
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
        if account.isSignedIn, let code = navigation.pendingInvite {
            navigation.pendingInvite = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { answering = InviteTarget(code: code) }
        }
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

    // A search result can open the app over any screen; the one on top closes first.
    private func openRequestedReminder() {
        guard let id = navigation.openRequest else { return }
        navigation.openRequest = nil
        guard !navigation.showingSignIn, !showingIntro, let reminder = store.reminder(id), reminder.deletedAt == nil else { return }
        let root = UIApplication.shared.mainWindow?.rootViewController
        if editing != nil || showingCalendar || composing != nil || showingLanguage || root?.presentedViewController != nil {
            editing = nil
            showingCalendar = false
            composing = nil
            showingLanguage = false
            viewingShared = nil
            inviting = false
            root?.dismiss(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { show(reminder) }
        } else {
            show(reminder)
        }
    }

    private func show(_ reminder: Reminder) {
        if reminder.shared != nil {
            viewingShared = SharedTarget(id: reminder.id)
        } else {
            editing = EditingTarget(reminder: reminder, isNew: false)
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
                    missed: Notifier.missedEnabled,
                    events: calendarFeed.day(timeline.date)
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
                habit: remote.isOn(.suggestions) ? Suggestions.habit(in: store.reminders.filter { $0.shared == nil }, now: timeline.date, calendar: .current, dismissed: dismissedHabits) : nil,
                onHabit: answerHabit,
                onPostpone: postpone,
                tip: tips.next(store: store, now: timeline.date),
                onTip: answerTip,
                loadingAccount: sync.loadingFirstTime,
                alert: homeAlert,
                onAlert: answerAlert,
                snoozeHint: remote.isOn(.suggestions) ? snoozeHint : nil,
                onSnoozeHint: answerSnoozeHint,
                onRemindEvent: remindEvent
            )
        }
    }

    // A calendar event becomes a reminder at its start with a quarter of an hour ahead.
    private func remindEvent(_ event: HomeContent.Event) {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: event.start)
        let reminder = Reminder(title: HomeContent.reminderTitle(event.title), schedule: Schedule(start: LocalDate(event.start, in: calendar), time: LocalTime(hour: parts.hour ?? 9, minute: parts.minute ?? 0)), preAlerts: [15], createdAt: Date())
        withAnimation(Motion.standard) { store.save(reminder) }
        Feedback.play(.save)
        Notifier.shared.requestPermissionIfNeeded()
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
            edit(row.reminderID)
            return
        }
        guard let reminder = store.reminder(row.reminderID) else { return }
        // Putting off a shared reminder is personal, the friends keep their time.
        if reminder.schedule?.rule == nil, reminder.shared == nil {
            _ = move(row.reminderID, to: date)
        } else {
            withAnimation(Motion.standard) { store.snooze(row.reminderID, until: date) }
        }
        Feedback.play(.save)
    }

    // Put off three times in a row, the time itself is probably wrong.
    private var snoozeHint: SnoozeHint? {
        _ = store.reminders
        guard let reminder = store.activeReminders.first(where: { SnoozeStats.count($0.id) >= 3 && $0.shared?.isMine != false }) else { return nil }
        return SnoozeHint(reminderID: reminder.id, title: reminder.title)
    }

    private func answerSnoozeHint(_ hint: SnoozeHint, accepted: Bool) {
        SnoozeStats.reset(hint.reminderID)
        store.reloadIfChanged(edit: false)
        if accepted {
            edit(hint.reminderID)
        }
    }

    private var homeAlert: HomeAlert? {
        if store.writeFailed { return .storageFull }
        // A friend's invitation waits on the main screen until it is answered; nothing else shows it.
        if let invited = store.reminders.first(where: { $0.deletedAt == nil && $0.shared?.isInvitation == true }), let shared = invited.shared {
            let name = SharedService.shared.name(of: shared.owner.id, fallback: shared.owner.name)
            return .invitation(invited.id, String(localized: "\(name) shares a reminder with you: \(invited.title)", bundle: .app, locale: .app))
        }
        if let title = SharedService.shared.state.refused {
            return .notShared(String(localized: "“\(title)” could not be shared and stays only on this phone.", bundle: .app, locale: .app))
        }
        if let title = SharedService.shared.state.refusedChange {
            return .notShared(String(localized: "The change to “\(title)” did not reach the friends.", bundle: .app, locale: .app))
        }
        if NotificationAccess.shared.denied { return .notificationsOff }
        if account.expired, !account.isSignedIn { return .signInExpired }
        return nil
    }

    // https://remaapp.cc/i/CODE opens the answer to a friend's invitation.
    private func openInvite(_ url: URL?) {
        guard let url, url.scheme == "https", ["remaapp.cc", "www.remaapp.cc"].contains(url.host() ?? "") else { return }
        let parts = url.pathComponents
        guard parts.count >= 3, parts[parts.count - 2] == "i" else { return }
        let code = parts[parts.count - 1].uppercased()
        guard code.count == 8, code.allSatisfy({ $0.isLetter || $0.isNumber }) else { return }
        // Whatever is open closes first, a sheet cannot show over another one.
        let root = UIApplication.shared.mainWindow?.rootViewController
        if editing != nil || checking != nil || composing != nil || showingCalendar || inviting || viewingShared != nil || root?.presentedViewController != nil {
            editing = nil
            checking = nil
            composing = nil
            showingCalendar = false
            inviting = false
            viewingShared = nil
            root?.dismiss(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { answering = InviteTarget(code: code) }
        } else {
            answering = InviteTarget(code: code)
        }
    }

    private func answerAlert(_ alert: HomeAlert) {
        switch alert {
        case .storageFull, .notificationsOff:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        case .signInExpired:
            navigation.showingSignIn = true
        case .invitation(let id, _):
            viewingShared = SharedTarget(id: id)
        case .notShared:
            SharedService.shared.clearRefused()
        }
    }

    private func answerTip(_ tip: Tip, accepted: Bool) {
        tips.dismiss(tip)
        if tip == .weather, accepted {
            Task { await WeatherAdvisor.shared.setEnabled(true) }
        }
        if tip == .friends, accepted {
            navigation.path.append(.friends)
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
        guard let original = store.reminder(id), original.schedule?.rule == nil, original.shared?.isMine != false else { return nil }
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

    // A reminder with a list opens the list to tick, the editor is one tap further.
    private func open(_ id: UUID) {
        guard let reminder = store.reminder(id) else { return }
        if reminder.shared != nil {
            viewingShared = SharedTarget(id: id)
        } else if reminder.items.isEmpty {
            editing = EditingTarget(reminder: reminder, isNew: false)
        } else {
            checking = ChecklistTarget(id: id)
        }
    }

    // Only the one who made a shared reminder changes it, the others see it with its participants.
    private func edit(_ id: UUID) {
        guard let reminder = store.reminder(id) else { return }
        if let shared = reminder.shared, !shared.isMine {
            viewingShared = SharedTarget(id: id)
            return
        }
        editing = EditingTarget(reminder: reminder, isNew: false)
    }
}
