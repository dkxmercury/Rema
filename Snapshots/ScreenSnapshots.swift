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
    func render<Screen: View>(_ screen: Screen, name: String, style: UIUserInterfaceStyle, height: CGFloat = 844) throws {
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
        let device = ViewImageConfig.iPhone13
        let config = ViewImageConfig(safeArea: device.safeArea, size: CGSize(width: 390, height: height), traits: device.traits)
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
