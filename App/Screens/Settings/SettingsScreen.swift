import CoreLocation
import RemaCore
import SwiftUI
import UserNotifications

struct SettingsScreen: View {
    let store: Store
    var locale: Locale = AppLanguage.current.locale
    var account: AccountScreen.Summary?
    var onSound: () -> Void = {}
    var onPlaces: () -> Void = {}
    var onSignIn: () -> Void = {}
    var onAccount: () -> Void = {}
    var onLanguage: () -> Void = {}
    var onCity: () -> Void = {}
    var onFeatures: () -> Void = {}
    let onBack: () -> Void

    @AppStorage(Feedback.hapticsKey) private var haptics = true
    @AppStorage(Feedback.soundsKey) private var sounds = true
    @AppStorage(Notifier.missedKey) private var missed = true
    @State private var editingTime: TimeTarget?
    @State private var permissions = Permissions()
    @State private var weather = WeatherAdvisor.shared
    @State private var lock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    struct TimeTarget: Identifiable {
        enum Kind {
            case morning
            case evening
        }

        let kind: Kind
        var id: Kind { kind }
    }

    struct Permissions: Equatable {
        var notifications: UNAuthorizationStatus = .notDetermined
        var urgent: UNNotificationSetting = .notSupported
        var location: CLAuthorizationStatus = .notDetermined
    }

    private var describer: Describer {
        Describer(calendar: .current, locale: locale)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("Account", top: 14) { accountPanel }
                    if lock.available {
                        section("Protection") {
                            PanelList {
                                ToggleRow(icon: Icons.faceID, iconColor: Palette.text, title: "\(lock.biometryName) sign-in", subtitle: String(localized: "Rema opens only after \(lock.biometryName)"), isOn: lockBinding, minHeight: 60)
                                if lock.enabled {
                                    Hairline()
                                    lockDelayRow
                                }
                            }
                            Text("Widgets and notifications stay open. If \(lock.biometryName) does not work, you can enter the phone passcode.")
                                .font(.app(.golos, 13))
                                .lineHeight(18, .golos, 13)
                                .foregroundStyle(Palette.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 4)
                        }
                    }
                    section("Sound") {
                        PanelList {
                            NavigationRow(icon: Icons.note, iconColor: Palette.text, title: "Default sound", minHeight: 52, action: onSound) {
                                value(describer.soundName(store.settings.defaultSound, settings: store.settings, sounds: store.sounds))
                            }
                        }
                    }
                    section("Time") {
                        PanelList {
                            NavigationRow(icon: Icons.sun, iconColor: Palette.text, title: "Morning", action: { editingTime = TimeTarget(kind: .morning) }) {
                                clock(store.settings.morning)
                            }
                            Hairline()
                            NavigationRow(icon: Icons.moon, iconColor: Palette.text, title: "Evening", action: { editingTime = TimeTarget(kind: .evening) }) {
                                clock(store.settings.evening)
                            }
                            Hairline()
                            nagRow
                            if Remote.shared.isOn(.missed) {
                                Hairline()
                                ToggleRow(icon: Icons.bell, iconColor: Palette.text, title: "Missed reminders", subtitle: String(localized: "a badge on the icon and one more reminder in \(Int(Remote.shared.number(.missedFollowUp))) minutes"), isOn: $missed, minHeight: 60)
                                    .onChange(of: missed) { _, _ in Notifier.shared.scheduleSoon() }
                            }
                        }
                        Text("For the words “morning” and “evening” and reminders without a time")
                            .font(.app(.golos, 13))
                            .lineHeight(18, .golos, 13)
                            .foregroundStyle(Palette.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                    section("Places") {
                        PanelList {
                            NavigationRow(icon: Icons.pin, iconColor: Palette.text, title: "My places", minHeight: 52, action: onPlaces) {
                                value(String(localized: "\(store.activePlaces.count) of \(20)"))
                            }
                        }
                    }
                    if weather.available {
                        section("Weather") {
                            PanelList {
                                ToggleRow(icon: Icons.sun, iconColor: Palette.text, title: "Weather notifications", subtitle: String(localized: "in the evening about tomorrow and in the morning about today, only when there is a reason"), isOn: weatherBinding, minHeight: 64)
                                if weather.enabled {
                                    Hairline()
                                    NavigationRow(icon: Icons.pin, iconColor: Palette.text, title: "City", minHeight: 52, action: onCity) {
                                        value(weather.city ?? String(localized: "Not chosen"))
                                    }
                                }
                            }
                            weatherAttribution
                        }
                    }
                    section("Theme") {
                        Segmented(options: [(Appearance.system, "As in system"), (Appearance.light, "Light"), (Appearance.dark, "Dark")], selection: appearance, fontSize: 14)
                    }
                    section("Feedback") {
                        PanelList {
                            ToggleRow(icon: Icons.vibration, iconColor: Palette.text, title: "Vibration", subtitle: String(localized: "a light response to touches"), isOn: $haptics, minHeight: 56)
                            Hairline()
                            ToggleRow(icon: Icons.speaker, iconColor: Palette.text, title: "Interface sounds", subtitle: String(localized: "quiet clicks, silent in silent mode"), isOn: $sounds, minHeight: 56)
                        }
                    }
                    section("Language") {
                        PanelList {
                            NavigationRow(icon: Icons.globe, iconColor: Palette.text, title: "App language", minHeight: 52, action: onLanguage) {
                                value(AppLanguage.current.nativeName)
                            }
                        }
                    }
                    section("Permissions") {
                        PanelList {
                            permissionRow("Notifications", granted: notificationsGranted, text: notificationsText, height: 49, action: notificationsAction)
                            Hairline()
                            permissionRow("Urgent notifications", granted: permissions.urgent == .enabled, text: permissions.urgent == .enabled ? String(localized: "allowed") : String(localized: "not allowed"), height: 49, action: openSystemSettings)
                            Hairline()
                            permissionRow("Location", granted: locationGranted, text: locationText, height: 50, action: openSystemSettings)
                        }
                    }
                    about
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "Settings", leading: .back, action: onBack)
            }
        }
        .foregroundStyle(Palette.text)
        .sheet(item: $editingTime) { target in
            TimeSheet(
                title: target.kind == .morning ? "Morning" : "Evening",
                time: target.kind == .morning ? store.settings.morning : store.settings.evening
            ) { time in
                store.update { settings in
                    if target.kind == .morning {
                        settings.morning = time
                    } else {
                        settings.evening = time
                    }
                }
                editingTime = nil
            }
        }
        .task(id: scenePhase) {
            await refreshPermissions()
        }
        .onChange(of: haptics) { _, _ in Feedback.play(.toggle) }
        .onChange(of: sounds) { _, _ in Feedback.play(.toggle) }
    }

    private var lockBinding: Binding<Bool> {
        Binding(get: { lock.enabled }, set: { on in
            Task {
                await lock.setEnabled(on)
                Feedback.play(lock.enabled == on ? .toggle : .error)
            }
        })
    }

    private func lockDelayText(_ seconds: Int) -> String {
        switch seconds {
        case 0: return String(localized: "right away")
        case 60: return String(localized: "after a minute")
        default: return String(localized: "after \(seconds / 60) minutes")
        }
    }

    private var lockDelayRow: some View {
        Menu {
            ForEach([0, 60, 300], id: \.self) { seconds in
                Button {
                    lock.setDelay(seconds)
                    Feedback.play(.select)
                } label: {
                    if seconds == lock.delay {
                        Label(lockDelayText(seconds), systemImage: "checkmark")
                    } else {
                        Text(verbatim: lockDelayText(seconds))
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Glyph(paths: Icons.clock, size: 20, lineWidth: 2, color: Palette.text)
                Text("Lock")
                    .font(.app(.golos, 16, weight: 500))
                    .frame(maxWidth: .infinity, alignment: .leading)
                value(lockDelayText(lock.delay))
                Glyph(paths: Icons.chevron, size: 16, lineWidth: 2, color: Palette.secondary)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .foregroundStyle(Palette.text)
        }
    }

    private var weatherBinding: Binding<Bool> {
        Binding(get: { weather.enabled }, set: { on in
            Feedback.play(.toggle)
            Task { await weather.setEnabled(on) }
        })
    }

    private var weatherAttribution: some View {
        HStack(spacing: 8) {
            if let mark = colorScheme == .dark ? weather.markDark : weather.markLight {
                AsyncImage(url: mark) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(height: 12)
                .accessibilityLabel(Text(verbatim: "Apple Weather"))
            }
            Spacer(minLength: 8)
            if let legal = weather.legal {
                Link(destination: legal) {
                    Text("Data sources")
                        .font(.app(.golos, 13, weight: 600))
                        .foregroundStyle(Palette.accentText)
                        .frame(minHeight: 32)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .task { await weather.loadAttribution() }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, top: CGFloat = 16, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            content()
        }
        .padding(.top, top)
    }

    @ViewBuilder
    private var accountPanel: some View {
        if let account {
            Button(action: onAccount) {
                HStack(spacing: 12) {
                    let badge = RoundedRectangle(cornerRadius: 10, style: .circular)
                    Glyph(paths: Icons.cloudCheck, size: 20, lineWidth: 2.1, color: Palette.onAccent)
                        .frame(width: 36, height: 36)
                        .background(badge.fill(Palette.accent).insetShadow(badge, .black.opacity(0.14), y: -2))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: account.email.isEmpty ? String(localized: "Apple ID with a hidden email") : account.email)
                            .font(.app(.golos, 16, weight: 600))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(account.status == .offline ? LocalizedStringKey("No connection, changes will be saved later") : LocalizedStringKey("Reminders are saved in the account"))
                            .font(.app(.golos, 13))
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Glyph(paths: Icons.chevron, size: 16, lineWidth: 2, color: Palette.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .panel()
        } else {
            invite
        }
    }

    private var invite: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                let badge = RoundedRectangle(cornerRadius: 10, style: .circular)
                Glyph(paths: Icons.cloudCheck, size: 20, lineWidth: 2.1, color: Palette.onAccent)
                    .frame(width: 36, height: 36)
                    .background(badge.fill(Palette.accent).insetShadow(badge, .black.opacity(0.14), y: -2))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign in to keep your reminders")
                        .font(.app(.golos, 16, weight: 600))
                    Text("They will live in your account and appear on any of your phones.")
                        .font(.app(.golos, 13))
                        .lineHeight(18, .golos, 13)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: onSignIn) {
                let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
                Text("Sign in")
                    .font(.app(.golos, 15, weight: 600))
                    .foregroundStyle(Palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(shape.fill(Palette.accent).insetShadow(shape, .black.opacity(0.15), y: -3))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var nagRow: some View {
        Menu {
            ForEach([1, 2, 3, 5, 10, 15, 30], id: \.self) { minutes in
                Button {
                    store.update { $0.nagInterval = minutes }
                    Feedback.play(.select)
                } label: {
                    if minutes == store.settings.nagInterval {
                        Label(String(localized: "every \(minutes) minutes"), systemImage: "checkmark")
                    } else {
                        Text(verbatim: String(localized: "every \(minutes) minutes"))
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Glyph(paths: Icons.bell, size: 20, lineWidth: 2, color: Palette.text)
                Text("Repeat for persistent")
                    .font(.app(.golos, 16, weight: 500))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                value(String(localized: "every \(store.settings.nagInterval) minutes"))
                Glyph(paths: Icons.chevron, size: 16, lineWidth: 2, color: Palette.secondary)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .foregroundStyle(Palette.text)
        }
    }

    private func value(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.app(.golos, 14))
            .foregroundStyle(Palette.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private func clock(_ time: LocalTime) -> some View {
        Text(verbatim: String(format: "%d:%02d", time.hour, time.minute))
            .font(.app(.jost, 17, weight: 500))
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private func permissionRow(_ title: LocalizedStringKey, granted: Bool, text: String, height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.app(.golos, 16, weight: 500))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Circle()
                        .fill(granted ? Palette.yearly : Palette.urgent)
                        .frame(width: 8, height: 8)
                    Text(verbatim: text)
                        .font(.app(.golos, 14))
                        .foregroundStyle(granted ? Palette.granted : Palette.urgentText)
                }
            }
            .frame(minHeight: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    private var appearance: Binding<Appearance> {
        Binding(
            get: { store.settings.appearance },
            set: { value in store.update { $0.appearance = value } }
        )
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(verbatim: "Rema")
            PanelList {
                NavigationRow(icon: Icons.star, iconColor: Palette.text, title: "What Rema can do", minHeight: 52, action: onFeatures) {
                    EmptyView()
                }
                Hairline()
                LinkRow(icon: Icons.instagram, title: "Instagram", value: "@rema.apps", url: Remote.shared.link(.instagram))
                Hairline()
                LinkRow(icon: Icons.envelope, title: "Write to support", url: Remote.shared.link(.support))
                Hairline()
                LinkRow(icon: Icons.document, title: "Privacy policy", url: Remote.shared.link(.privacy))
                Hairline()
                LinkRow(icon: Icons.document, title: "Terms of use", url: Remote.shared.link(.terms))
            }
            Text(verbatim: version)
                .font(.app(.golos, 12))
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
        .padding(.top, 16)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "Rema \(short) (\(build))"
    }

    private var notificationsGranted: Bool {
        [.authorized, .provisional, .ephemeral].contains(permissions.notifications)
    }

    private var notificationsText: String {
        switch permissions.notifications {
        case .notDetermined: return String(localized: "not requested")
        case .denied: return String(localized: "off")
        default: return String(localized: "on")
        }
    }

    private var locationGranted: Bool {
        permissions.location == .authorizedAlways || permissions.location == .authorizedWhenInUse
    }

    private var locationText: String {
        switch permissions.location {
        case .authorizedAlways: return String(localized: "always")
        case .authorizedWhenInUse: return String(localized: "while using")
        case .notDetermined: return String(localized: "not asked")
        default: return String(localized: "no access")
        }
    }

    private func notificationsAction() {
        if permissions.notifications == .notDetermined {
            Task {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                await refreshPermissions()
                Notifier.shared.scheduleSoon()
            }
        } else {
            openSystemSettings()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func refreshPermissions() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        var updated = Permissions()
        updated.notifications = settings.authorizationStatus
        updated.urgent = settings.timeSensitiveSetting
        updated.location = CLLocationManager().authorizationStatus
        permissions = updated
    }
}

struct TimeSheet: View {
    let title: LocalizedStringKey
    let onDone: (LocalTime) -> Void
    @State private var hour: Int
    @State private var minute: Int

    init(title: LocalizedStringKey, time: LocalTime, onDone: @escaping (LocalTime) -> Void) {
        self.title = title
        self.onDone = onDone
        _hour = State(initialValue: time.hour)
        _minute = State(initialValue: time.minute)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.app(.jost, 18, weight: 500))
                .padding(.top, 24)
            TimeDrums(hour: $hour, minute: $minute)
                .padding(.top, 18)
            Button {
                Feedback.play(.save)
                onDone(LocalTime(hour: hour, minute: minute))
            } label: {
                Text("Done")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 18)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .foregroundStyle(Palette.text)
        .presentationDetents([.height(400)])
        .presentationCornerRadius(28)
        .presentationBackground(Palette.background)
    }
}

struct LinkRow: View {
    let icon: [String]
    let title: LocalizedStringKey
    var value: String?
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 12) {
                Glyph(paths: icon, size: 20, lineWidth: 2, color: Palette.text)
                Text(title)
                    .font(.app(.golos, 16, weight: 500))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    Text(verbatim: value)
                        .font(.app(.golos, 14))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                Glyph(paths: Icons.external, size: 16, lineWidth: 2, color: Palette.secondary)
            }
            .frame(minHeight: 51)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}
