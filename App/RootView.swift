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
}

// Lives outside the views, so the screen stack survives when a language change rebuilds them.
@MainActor
@Observable
final class RootNavigation {
    static let shared = RootNavigation()
    static let welcomeKey = "welcomeDone"

    var path: [RootRoute] = []
    var languageCode = AppLanguage.current.rawValue
    var showingSignIn = !Account.shared.isSignedIn && !UserDefaults.standard.bool(forKey: RootNavigation.welcomeKey)
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
        .alert("Update Rema", isPresented: .constant(remote.needsUpdate && !navigation.showingSignIn)) {
            Button("Open App Store") { openURL(remote.link(.appStore)) }
        } message: {
            Text(verbatim: remote.text(remote.config.update) ?? String(localized: "This version is out of date. Install the new one from the App Store, it takes a minute."))
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
        .onAppear { showAnnouncementIfNew() }
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
                onBack: { navigation.path.removeLast() }
            )
        case .defaultSound:
            SoundScreen(store: store, choice: defaultSound) { navigation.path.removeLast() }
        case .places:
            PlacesListScreen(store: store, onOpen: { navigation.path.append(.place($0.id)) }, onAdd: { navigation.path.append(.place(nil)) }, onBack: { navigation.path.removeLast() })
        case .place(let id):
            NewPlaceScreen(store: store, existing: store.places.first { $0.id == id }, onSaved: { _ in navigation.path.removeLast() }, onBack: { navigation.path.removeLast() })
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
                    onDelete: {
                        try await SyncService.shared.deleteAccount()
                        navigation.path.removeAll { $0 == .account }
                    },
                    onBack: { navigation.path.removeLast() }
                )
            } else {
                Color.clear
            }
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
            places: store.activePlaces.count
        )
    }

    private func finishSignIn(_ signedIn: Bool) {
        UserDefaults.standard.set(true, forKey: RootNavigation.welcomeKey)
        navigation.showingSignIn = false
        if signedIn {
            SyncService.shared.becameActive()
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
                    locale: AppLanguage.current.locale
                ),
                onToggle: toggle,
                onOpen: open,
                onCompose: { composing = ComposeTarget(voice: false) },
                onVoice: {
                    Feedback.play(.select)
                    composing = ComposeTarget(voice: true)
                },
                onCalendar: { showingCalendar = true },
                onSettings: { navigation.path.append(.settings) },
                zoom: zoom,
                onDelete: { id in
                    withAnimation(Motion.standard) { store.delete(id) }
                }
            )
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
