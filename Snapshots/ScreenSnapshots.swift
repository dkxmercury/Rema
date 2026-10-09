import SnapshotTesting
import SwiftUI
import XCTest
@testable import Rema

final class ScreenSnapshots: XCTestCase {
    func testHome() throws {
        try render(HomeScreen(content: SampleData.home), name: "D-Home", style: .light)
        try render(HomeScreen(content: SampleData.home), name: "D-Home-Dark", style: .dark)
    }

    func testScheduled() throws {
        let content = ScheduledContent.make(reminders: SampleData.reminders, places: SampleData.places, now: SampleData.now, calendar: SampleData.calendar, locale: russian)
        let count = ScheduledContent.count(reminders: SampleData.reminders, now: SampleData.now, calendar: SampleData.calendar)
        try render(ScheduledScreen(content: content, onBack: {}), name: "D-Scheduled", style: .light)
        try render(ScheduledScreen(content: content, onBack: {}), name: "Dark-Scheduled", style: .dark)
        try render(HomeScreen(content: SampleData.home, scheduledCount: count), name: "Home-Scheduled", style: .dark)
    }

    func testOtherReading() throws {
        try render(PhraseScreen(store: sampleStore(), text: "в 7 ужин с семьёй", now: SampleData.now, calendar: SampleData.calendar, locale: russian, autofocus: false, onClose: {}), name: "Phrase-OtherReading", style: .dark)
    }

    func testSafeAreaProbe() throws {
        try render(SafeAreaProbe(), name: "Probe", style: .light)
    }

    func testEditor() throws {
        let store = sampleStore()
        for (name, style) in [("D-Editor", UIUserInterfaceStyle.light), ("D-Editor-Dark", .dark)] {
            try render(EditorScreen(draft: SampleData.server, isNew: false, store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onClose: {}), name: name, style: style)
        }
    }

    func testDateTime() throws {
        let initial = SampleData.calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 10, minute: 0))!
        try render(DateTimeScreen(initial: initial, now: SampleData.now, settings: .standard(at: SampleData.now), calendar: SampleData.calendar, locale: russian, onDone: { _ in }, onClose: {}), name: "D-DateTime", style: .light)
    }

    func testRepeat() throws {
        try render(RepeatScreen(draft: .constant(SampleData.server), now: SampleData.now, calendar: SampleData.calendar, locale: russian, onBack: {}), name: "D-Repeat", style: .light)
    }

    func testSnooze() throws {
        try render(SnoozeScreen(store: sampleStore(), onBack: {}), name: "D-Snooze", style: .light)
        try render(HomeScreen(content: SampleData.home, snoozeHint: SnoozeHint(reminderID: UUID(), title: "Позвонить поставщику")), name: "Home-SnoozeHint", style: .light)
    }

    func testRepeatWeekdays() throws {
        try render(RepeatScreen(draft: .constant(SampleData.reminders[3]), now: SampleData.now, calendar: SampleData.calendar, locale: russian, onBack: {}), name: "D-Repeat-Weekdays", style: .light)
    }

    func testEarly() throws {
        try render(EarlyScreen(draft: .constant(SampleData.server), now: SampleData.now, calendar: SampleData.calendar, locale: russian, onBack: {}), name: "D-Before", style: .light)
    }

    func testPhrase() throws {
        try render(PhraseScreen(store: sampleStore(), text: "завтра в 9 позвонить маме", now: SampleData.now, calendar: SampleData.calendar, locale: russian, autofocus: false, onClose: {}), name: "D-Phrase", style: .light)
    }

    func testVoice() throws {
        let recognizer = VoiceRecognizer()
        recognizer.transcript = "напомни в пятницу вечером забрать костюм из химчистки"
        recognizer.listening = true
        try render(VoiceScreen(store: sampleStore(), now: SampleData.now, calendar: SampleData.calendar, locale: russian, recognizer: recognizer, live: false, onFinish: { _ in }), name: "D-Voice", style: .light)
    }

    func testCalendar() throws {
        try render(CalendarScreen(store: sampleStore(), now: SampleData.now, calendar: SampleData.calendar, locale: russian, onClose: {}), name: "D-Calendar", style: .light)
    }

    func testSettings() throws {
        try render(SettingsScreen(store: sampleStore(), locale: russian, onBack: {}), name: "D-Settings", style: .light, height: 1500)
    }

    func testSound() throws {
        try render(SoundScreen(store: sampleStore(), choice: .constant(.custom(SampleData.gong.id)), locale: russian, onBack: {}), name: "D-Sound", style: .light)
    }

    func testPlaces() throws {
        try render(PlacesScreen(store: sampleStore(), title: "Забрать посылку на почте", placeIDs: .constant([SampleData.work.id, SampleData.gym.id]), trigger: .constant(.leave), onNewPlace: {}, onBack: {}), name: "D-Places", style: .light)
        try render(PlacesListScreen(store: sampleStore(), onOpen: { _ in }, onAdd: {}, onBack: {}), name: "D-PlacesList", style: .light)
        try render(NewPlaceScreen(store: sampleStore(), prefill: SampleData.gym, onSaved: { _ in }, onBack: {}), name: "D-NewPlace", style: .light)
    }

    func testDark() throws {
        let store = sampleStore()
        try render(PhraseScreen(store: store, text: "завтра в 9 позвонить маме", now: SampleData.now, calendar: SampleData.calendar, locale: russian, autofocus: false, onClose: {}), name: "Dark-Phrase", style: .dark)
        try render(CalendarScreen(store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onClose: {}), name: "Dark-Calendar", style: .dark)
        try render(SettingsScreen(store: store, locale: russian, onBack: {}), name: "Dark-Settings", style: .dark, height: 1210)
        try render(SoundScreen(store: store, choice: .constant(.custom(SampleData.gong.id)), locale: russian, onBack: {}), name: "Dark-Sound", style: .dark)
        try render(DateTimeScreen(initial: SampleData.now.addingTimeInterval(72_000), now: SampleData.now, settings: .standard(at: SampleData.now), calendar: SampleData.calendar, locale: russian, onDone: { _ in }, onClose: {}), name: "Dark-DateTime", style: .dark)
        try render(PlacesScreen(store: store, title: "Забрать посылку", placeIDs: .constant([SampleData.work.id]), trigger: .constant(.leave), onNewPlace: {}, onBack: {}), name: "Dark-Places", style: .dark)
    }

    func testStates() throws {
        let empty = HomeContent.make(reminders: [], places: [], now: SampleData.now, calendar: SampleData.calendar, locale: russian)
        try render(HomeScreen(content: empty, loadingAccount: true), name: "Home-Loading", style: .dark)
        try render(HomeScreen(content: SampleData.home, alert: .notificationsOff), name: "Home-NotificationsOff", style: .light)
        try render(HomeScreen(content: HomeContent.make(reminders: SampleData.busyDay, places: [], now: SampleData.now, calendar: SampleData.calendar, locale: russian)), name: "Home-Many", style: .light)
        let recognizer = VoiceRecognizer()
        recognizer.failure = "Разрешите доступ к микрофону в Настройках, чтобы диктовать напоминания."
        recognizer.needsSettings = true
        try render(VoiceScreen(store: sampleStore(), now: SampleData.now, calendar: SampleData.calendar, locale: russian, recognizer: recognizer, live: false, onFinish: { _ in }), name: "Voice-Denied", style: .dark)
    }

    func testNews() throws {
        try render(HomeScreen(content: SampleData.home, bellCount: 3, update: "1.2"), name: "K-Update", style: .light)
        try render(HomeScreen(content: SampleData.home, bellCount: 12, update: "1.2"), name: "K-Update-Dark", style: .dark)
        try render(NewsConsentSheet(onAnswer: { _ in }).background(Palette.panel), name: "K-Consent", style: .light, height: 520)
        try render(NewsConsentSheet(onAnswer: { _ in }).background(Palette.panel), name: "K-Consent-Dark", style: .dark, height: 520)
    }

    func testChecklist() throws {
        let store = sampleStore()
        store.save(SampleData.groceries)
        try render(EditorScreen(draft: SampleData.groceries, isNew: false, store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onClose: {}), name: "D-Checklist-Editor", style: .dark, height: 1100)
        try render(PhraseScreen(store: store, text: "завтра в 19 купить продукты", now: SampleData.now, calendar: SampleData.calendar, locale: russian, autofocus: false, onClose: {}), name: "D-Checklist-Phrase", style: .dark, height: 1000)
        try render(ChecklistSheet(store: store, reminderID: SampleData.groceries.id, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onEdit: {}, onClose: {}), name: "D-Checklist-Sheet", style: .dark, height: 560)
        let home = HomeContent.make(reminders: SampleData.reminders.filter { $0.title != "Купить хлеб и молоко" } + [SampleData.groceries], places: SampleData.places, now: SampleData.now, calendar: SampleData.calendar, locale: russian)
        try render(HomeScreen(content: home), name: "Home-Checklist", style: .dark)
    }

    func testHistory() throws {
        let done = DoneContent.make(reminders: SampleData.withHistory, now: SampleData.now, calendar: SampleData.calendar, locale: russian)
        let content = ScheduledContent.make(reminders: SampleData.reminders, places: SampleData.places, now: SampleData.now, calendar: SampleData.calendar, locale: russian)
        try render(ScheduledScreen(content: content, done: done, onBack: {}, tab: .done), name: "D-History", style: .dark, height: 1400)
    }

    func testMulti() throws {
        try render(PhraseScreen(store: sampleStore(), text: "завтра в 9 позвонить маме, в 12 обед с Ильёй, вечером купить хлеб", now: SampleData.now, calendar: SampleData.calendar, locale: russian, autofocus: false, onClose: {}), name: "D-Multi", style: .dark)
        try render(PhraseScreen(store: sampleStore(), text: "каждый день в 9 и 21 пить таблетки", now: SampleData.now, calendar: SampleData.calendar, locale: russian, autofocus: false, onClose: {}), name: "D-Multi-Times", style: .light)
    }

    func testRepeatMonthly() throws {
        try render(RepeatScreen(draft: .constant(SampleData.monthlyReport), now: SampleData.now, calendar: SampleData.calendar, locale: russian, onBack: {}), name: "D-Repeat-Monthly", style: .light, height: 1000)
    }

    func testLargeText() throws {
        AppFonts.scale = AppFonts.scale(for: .accessibility1)
        defer { AppFonts.scale = 1 }
        let store = sampleStore()
        try render(HomeScreen(content: SampleData.home), name: "Large-Home", style: .light)
        try render(EditorScreen(draft: SampleData.server, isNew: false, store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onClose: {}), name: "Large-Editor", style: .light, height: 1300)
        try render(PhraseScreen(store: store, text: "завтра в 9 позвонить маме", now: SampleData.now, calendar: SampleData.calendar, locale: russian, autofocus: false, onClose: {}), name: "Large-Phrase", style: .light)
        try render(SettingsScreen(store: store, locale: russian, onBack: {}), name: "Large-Settings", style: .light, height: 1900)
    }

    func testSmallPhone() throws {
        let store = sampleStore()
        store.save(SampleData.groceries)
        try render(HomeScreen(content: SampleData.home), name: "SE-Home", style: .light, width: 375, height: 667)
        try render(PhraseScreen(store: store, text: "завтра в 9 позвонить маме", now: SampleData.now, calendar: SampleData.calendar, locale: russian, autofocus: false, onClose: {}), name: "SE-Phrase", style: .light, width: 375, height: 667)
        try render(EditorScreen(draft: SampleData.groceries, isNew: false, store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onClose: {}), name: "SE-Editor", style: .dark, width: 375, height: 667)
        try render(ChecklistSheet(store: store, reminderID: SampleData.groceries.id, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onEdit: {}, onClose: {}), name: "SE-Sheet", style: .light, width: 375, height: 500)
    }

    func testEmptyAndRightToLeft() throws {
        let empty = HomeContent.make(reminders: [], places: [], now: SampleData.now, calendar: SampleData.calendar, locale: russian)
        try render(HomeScreen(content: empty), name: "Home-Empty", style: .light)
        try render(HomeScreen(content: SampleData.home).environment(\.layoutDirection, .rightToLeft), name: "RTL-Home", style: .light)
        let store = sampleStore()
        try render(EditorScreen(draft: SampleData.server, isNew: false, store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onClose: {}).environment(\.layoutDirection, .rightToLeft), name: "RTL-Editor", style: .light)
        try render(CalendarScreen(store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onClose: {}).environment(\.layoutDirection, .rightToLeft), name: "RTL-Calendar", style: .light)
    }

    func testAccountScreens() throws {
        try render(WelcomeScreen(onEmail: {}, onLanguage: {}, onSkip: {}, onSignedIn: {}), name: "D-Welcome", style: .light)
        try render(WelcomeScreen(onEmail: {}, onLanguage: {}, onSkip: {}, onSignedIn: {}), name: "Dark-Welcome", style: .dark)
        try render(EmailScreen(mode: .signIn, email: "name@example.com", password: String(repeating: "x", count: 10), onReset: { _ in }, onSignedIn: {}, onBack: {}), name: "D-SignIn", style: .light)
        try render(EmailScreen(mode: .signUp, email: "name@example.com", password: String(repeating: "x", count: 10), onReset: { _ in }, onSignedIn: {}, onBack: {}), name: "D-SignUp", style: .light)
        try render(ResetScreen(email: "name@example.com", sentAt: SampleData.now, onBack: {}), name: "D-Reset", style: .light)
        try render(LanguageScreen(onClose: {}), name: "D-Language", style: .light)
        let summary = AccountScreen.Summary(email: "name@example.com", method: .apple, status: .saved, savedAt: Date(), reminders: 24, places: 4)
        try render(AccountScreen(summary: summary, locale: russian, onBack: {}), name: "D-Account", style: .light)
        try render(AccountScreen(summary: summary, locale: russian, onBack: {}), name: "Dark-Account", style: .dark)
        try render(SettingsScreen(store: sampleStore(), locale: russian, account: summary, onBack: {}), name: "Settings-SignedIn", style: .light, height: 1500)
    }

    private var russian: Locale { Locale(identifier: "ru_RU") }

    private func sampleStore() -> Store {
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        store.seed(reminders: SampleData.reminders, places: SampleData.places, sounds: [SampleData.gong])
        return store
    }
}

private struct SafeAreaProbe: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.red).frame(height: 4)
            Spacer(minLength: 0)
            Rectangle().fill(Color.blue).frame(height: 4)
        }
        .background(Color.white.ignoresSafeArea())
    }
}

private extension ScreenSnapshots {
    func render<Screen: View>(_ screen: Screen, name: String, style: UIUserInterfaceStyle, width: CGFloat = 390, height: CGFloat = 844) throws {
        guard let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else {
            throw XCTSkip("SNAPSHOT_DIR не задан")
        }
        let view = AnyView(
            screen
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .environment(\.colorScheme, style == .dark ? .dark : .light)
                .environment(\.mapsEnabled, false)
                .environment(\.introAnimations, false)
        )
        let device = width < 390 ? ViewImageConfig.iPhone8 : ViewImageConfig.iPhone13
        let config = ViewImageConfig(safeArea: device.safeArea, size: CGSize(width: width, height: height), traits: device.traits)
        let strategy = Snapshotting<AnyView, UIImage>.image(
            layout: .device(config: config),
            traits: UITraitCollection(userInterfaceStyle: style)
        )
        let finished = expectation(description: name)
        var output: UIImage?
        strategy.snapshot(view).run { image in
            output = image
            finished.fulfill()
        }
        wait(for: [finished], timeout: 60)
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try XCTUnwrap(output?.pngData()).write(to: url)
    }
}
