import RemaCore
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Rema

final class StoreSnapshots: XCTestCase {
    func testStoreScreens() throws {
        let previous = AppLanguage.current
        defer { AppLanguage.choose(previous) }
        for language in [AppLanguage.english, .russian] {
            AppLanguage.choose(language)
            let sample = StoreSample(language: language)
            let store = sample.store()
            let code = language.rawValue
            try shoot(HomeScreen(content: sample.home(at: sample.now)), "\(code)-01-home", sample)
            try shoot(PhraseScreen(store: store, text: sample.phrase, now: sample.now, calendar: sample.calendar, locale: sample.locale, autofocus: false, onClose: {}), "\(code)-02-phrase", sample)
            let recognizer = VoiceRecognizer()
            recognizer.transcript = sample.spoken
            recognizer.listening = true
            try shoot(VoiceScreen(store: store, now: sample.now, calendar: sample.calendar, locale: sample.locale, recognizer: recognizer, live: false, onFinish: { _ in }), "\(code)-03-voice", sample)
            try shoot(CalendarScreen(store: store, now: sample.now, calendar: sample.calendar, locale: sample.locale, onClose: {}), "\(code)-04-calendar", sample)
            try shoot(EditorScreen(draft: sample.server, isNew: false, store: store, now: sample.now, calendar: sample.calendar, locale: sample.locale, onClose: {}), "\(code)-05-editor", sample)
            try shoot(WelcomeScreen(onEmail: {}, onLanguage: {}, onSkip: {}, onSignedIn: {}), "\(code)-06-account", sample)
            try shoot(HomeScreen(content: sample.home(at: sample.later, missed: true)), "\(code)-07-missed", sample)
            try shoot(HomeScreen(content: sample.home(at: sample.now)), "\(code)-08-dark", sample, style: .dark)
            try shoot(PhraseScreen(store: store, text: sample.weekly, now: sample.now, calendar: sample.calendar, locale: sample.locale, autofocus: false, onClose: {}), "\(code)-09-repeat", sample, style: .dark)
            try shoot(FeaturesScreen(onBack: {}), "\(code)-10-features", sample)
            // The site shows these when the visitor's phone is in dark mode.
            try shoot(VoiceScreen(store: store, now: sample.now, calendar: sample.calendar, locale: sample.locale, recognizer: recognizer, live: false, onFinish: { _ in }), "\(code)-site-dark-voice", sample, style: .dark)
            try shoot(CalendarScreen(store: store, now: sample.now, calendar: sample.calendar, locale: sample.locale, onClose: {}), "\(code)-site-dark-calendar", sample, style: .dark)
            try shoot(EditorScreen(draft: sample.server, isNew: false, store: store, now: sample.now, calendar: sample.calendar, locale: sample.locale, onClose: {}), "\(code)-site-dark-editor", sample, style: .dark)
            try shoot(HomeScreen(content: sample.home(at: sample.later, missed: true)), "\(code)-site-dark-missed", sample, style: .dark)
            try shoot(FeaturesScreen(onBack: {}), "\(code)-site-dark-features", sample, style: .dark)
        }
    }

    func testWatchScreen() throws {
        guard let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else {
            throw XCTSkip("SNAPSHOT_DIR не задан")
        }
        let previous = AppLanguage.current
        defer {
            AppLanguage.choose(previous)
            WatchLanguage.use(nil)
        }
        let titles = [
            "en": ["Take vitamins", "Call the supplier", "Buy bread and milk", "Water the plants"],
            "ru": ["Выпить витамины", "Позвонить поставщику", "Купить хлеб и молоко", "Полить цветы"],
        ]
        for (code, language) in [("en", AppLanguage.english), ("ru", .russian)] {
            AppLanguage.choose(language)
            WatchLanguage.use(code)
            let names = titles[code] ?? []
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            func at(_ hour: Int, _ minute: Int) -> Date {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
            }
            let now = at(13, 50)
            let items = [
                WatchItem(reminderID: UUID(), title: names[0], occurrence: at(9, 0), done: true, urgent: false),
                WatchItem(reminderID: UUID(), title: names[1], occurrence: at(14, 30), done: false, urgent: true),
                WatchItem(reminderID: UUID(), title: names[2], occurrence: at(19, 0), done: false, urgent: false),
                WatchItem(reminderID: UUID(), title: names[3], occurrence: at(21, 30), done: false, urgent: false),
            ]
            let screen = WatchHome(model: WatchModel(payload: WatchPayload(items: items, generated: now)), moment: now)
                .environment(\.locale, Locale(identifier: code))
                .environment(\.colorScheme, .dark)
            let traits = UITraitCollection { traits in
                traits.displayScale = 2
                traits.userInterfaceStyle = .dark
            }
            let config = ViewImageConfig(safeArea: .zero, size: CGSize(width: 198, height: 242), traits: traits)
            let strategy = Snapshotting<AnyView, UIImage>.image(layout: .device(config: config), traits: traits)
            let finished = expectation(description: "watch \(code)")
            var output: UIImage?
            strategy.snapshot(AnyView(screen)).run { image in
                output = image
                finished.fulfill()
            }
            wait(for: [finished], timeout: 60)
            let folder = URL(fileURLWithPath: directory).appendingPathComponent("store", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try XCTUnwrap(output?.pngData()).write(to: folder.appendingPathComponent("watch-\(code).png"))
        }
    }

    private func shoot<Screen: View>(_ screen: Screen, _ name: String, _ sample: StoreSample, style: UIUserInterfaceStyle = .light) throws {
        guard let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else {
            throw XCTSkip("SNAPSHOT_DIR не задан")
        }
        let view = AnyView(
            screen
                .environment(\.locale, sample.locale)
                .environment(\.colorScheme, style == .dark ? .dark : .light)
                .environment(\.mapsEnabled, false)
                .environment(\.introAnimations, false)
        )
        let traits = UITraitCollection { traits in
            traits.displayScale = 3
            traits.userInterfaceStyle = style
        }
        let config = ViewImageConfig(safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0), size: CGSize(width: 440, height: 956), traits: traits)
        let strategy = Snapshotting<AnyView, UIImage>.image(layout: .device(config: config), traits: traits)
        let finished = expectation(description: name)
        var output: UIImage?
        strategy.snapshot(view).run { image in
            output = image
            finished.fulfill()
        }
        wait(for: [finished], timeout: 60)
        let folder = URL(fileURLWithPath: directory).appendingPathComponent("store", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try XCTUnwrap(output?.pngData()).write(to: folder.appendingPathComponent("\(name).png"))
    }
}

struct StoreSample {
    let language: AppLanguage
    let calendar: Calendar
    let locale: Locale
    let now: Date
    let later: Date
    let work: Place
    let gym: Place
    let server: Reminder
    let parcel: Reminder
    let reminders: [Reminder]

    init(language: AppLanguage) {
        self.language = language
        let english = language == .english
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        calendar.locale = Locale(identifier: english ? "en_US" : "ru_RU")
        calendar.firstWeekday = english ? 1 : 2
        self.calendar = calendar
        locale = Locale(identifier: english ? "en_US" : "ru_RU")
        now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 13, minute: 50))!
        later = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 15, minute: 5))!
        let created = now
        work = Place(name: english ? "Work" : "Работа", icon: "work", latitude: 41.311, longitude: 69.279, radius: 200, createdAt: created)
        gym = Place(name: english ? "Gym" : "Спортзал", icon: "sport", latitude: 41.299, longitude: 69.240, radius: 100, createdAt: created)
        server = Reminder(
            title: english ? "Renew the domain" : "Оплатить сервер",
            schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 6), time: LocalTime(hour: 10, minute: 0), rule: .yearly(month: 10, day: 6)),
            preAlerts: [10_080, 1_440],
            nag: true,
            urgent: true,
            createdAt: created
        )
        parcel = Reminder(title: english ? "Pick up the parcel" : "Забрать посылку", schedule: nil, placeIDs: [work.id, gym.id], placeTrigger: .leave, createdAt: created)
        var vitamins = Reminder(
            title: english ? "Take vitamins" : "Выпить витамины",
            schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 1), time: LocalTime(hour: 9, minute: 0), rule: .daily),
            nag: true,
            createdAt: created
        )
        vitamins.completedThrough = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9, minute: 0))
        reminders = [
            vitamins,
            Reminder(title: english ? "Call the supplier" : "Позвонить поставщику", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 14, minute: 30)), preAlerts: [15], urgent: true, createdAt: created),
            Reminder(title: english ? "Buy bread and milk" : "Купить хлеб и молоко", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 19, minute: 0)), createdAt: created),
            Reminder(title: english ? "Water the plants" : "Полить цветы", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 1), time: LocalTime(hour: 21, minute: 30), rule: .weekly([.monday, .thursday])), createdAt: created),
            Reminder(title: english ? "Dentist" : "Стоматолог", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 14), time: LocalTime(hour: 15, minute: 0)), preAlerts: [1_440], createdAt: created),
            Reminder(title: english ? "Mom's birthday" : "День рождения мамы", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 22), time: LocalTime(hour: 9, minute: 0), rule: .yearly(month: 10, day: 22)), createdAt: created),
            parcel,
            server,
        ]
    }

    var phrase: String {
        language == .english ? "tomorrow at 9 call mom" : "завтра в 9 позвонить маме"
    }

    var weekly: String {
        language == .english ? "every Tue and Thu at 8 yoga" : "каждый вт и чт в 8 йога"
    }

    var spoken: String {
        language == .english ? "remind me on Friday evening to pick up the suit from the dry cleaner" : "напомни в пятницу вечером забрать костюм из химчистки"
    }

    func store() -> Store {
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        store.seed(reminders: reminders, places: [work, gym], sounds: [])
        return store
    }

    func home(at moment: Date, missed: Bool = false) -> HomeContent {
        HomeContent.make(reminders: reminders, places: [work, gym], now: moment, calendar: calendar, locale: locale, missed: missed)
    }
}
