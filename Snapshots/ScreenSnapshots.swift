import RemaCore
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
        let store = sampleStore()
        try render(ScheduledScreen(content: content, store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onBack: {}), name: "D-Scheduled", style: .light)
        try render(ScheduledScreen(content: content, store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onBack: {}), name: "Dark-Scheduled", style: .dark)
        try render(HomeScreen(content: SampleData.home, scheduledCount: count), name: "Home-Scheduled", style: .dark)
    }

    func testSearch() throws {
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        store.seed(reminders: SampleData.searchReminders, places: SampleData.places + [SampleData.sashaPlace], sounds: [])
        let content = ScheduledContent.make(reminders: store.reminders, places: store.places, now: SampleData.now, calendar: SampleData.calendar, locale: russian)
        for (name, style) in [("L-SearchResults", UIUserInterfaceStyle.light), ("L-SearchResults-Dark", .dark)] {
            try render(ScheduledScreen(content: content, store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onBack: {}, query: "саш"), name: name, style: style)
        }
    }

    func testPast() throws {
        let calendar = SampleData.calendar
        let locale = russian
        func at(_ day: Int, _ hour: Int) -> Schedule {
            Schedule(start: LocalDate(year: 2026, month: 10, day: day), time: LocalTime(hour: hour, minute: 0), timeZone: "Asia/Tashkent")
        }
        let anna = SharedInfo(owner: SharedPerson(id: "anna", name: "Аня"), status: SharedStatus.accepted, members: [SharedMember(id: "me", name: "Саша", status: SharedStatus.accepted)], doneMode: .each)
        let report = Reminder(title: "Отправить отчёт", schedule: at(5, 12), createdAt: SampleData.now)
        var pills = Reminder(title: "Купить таблетки", schedule: at(4, 19), createdAt: SampleData.now)
        pills.shared = anna
        let paper = Reminder(title: "Забрать справку", schedule: at(3, 10), createdAt: SampleData.now)
        let reminders = SampleData.reminders + [report, pills, paper]
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        store.seed(reminders: reminders, places: SampleData.places, sounds: [])
        let content = ScheduledContent.make(reminders: reminders, places: SampleData.places, now: SampleData.now, calendar: calendar, locale: russian)
        try render(ScheduledScreen(content: content, store: store, now: SampleData.now, calendar: calendar, locale: russian, onBack: {}), name: "R-PastScheduled", style: .light)
        try render(ScheduledScreen(content: content, store: store, now: SampleData.now, calendar: calendar, locale: russian, onBack: {}), name: "R-PastScheduled-Dark", style: .dark)
        let home = HomeContent.make(reminders: reminders, places: SampleData.places, now: SampleData.now, calendar: calendar, locale: russian)
        try render(HomeScreen(content: home), name: "R-PastHome", style: .light, height: 1100)
        try render(HomeScreen(content: home), name: "R-PastHome-Dark", style: .dark, height: 1100)

        var parcel = Reminder(title: "Забрать посылку", schedule: at(2, 18), createdAt: SampleData.now)
        parcel.shared = SharedInfo(owner: SharedPerson(id: "me", name: "Саша"), status: SharedStatus.accepted, members: [SharedMember(id: "anna", name: "Аня", status: SharedStatus.accepted)], doneMode: .each)
        parcel.markDone(through: calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 18)) ?? SampleData.now)
        var movie = Reminder(title: "Кино в субботу", schedule: at(10, 10), createdAt: SampleData.now)
        movie.shared = anna
        let rows = ZStack(alignment: .top) {
            Palette.background.ignoresSafeArea()
            PanelList {
                SharedReminderRow(reminder: pills, author: "автор Аня", now: SampleData.now, calendar: calendar, locale: locale, onOpen: {}, onToggle: { _, _ in })
                Hairline()
                SharedReminderRow(reminder: parcel, author: "автор вы", now: SampleData.now, calendar: calendar, locale: locale, onOpen: {}, onToggle: { _, _ in })
                Hairline()
                SharedReminderRow(reminder: movie, author: "автор Аня", now: SampleData.now, calendar: calendar, locale: locale, onOpen: {}, onToggle: { _, _ in })
            }
            .padding(.horizontal, 18)
            .padding(.top, 80)
        }
        try render(rows, name: "R-PastFriend", style: .light)
        try render(rows, name: "R-PastFriend-Dark", style: .dark)
    }

    func testSidePanel() throws {
        let calendar = SampleData.calendar
        let locale = russian
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        var ids: [UUID] = []
        store.update { settings in
            for name in ["Работа", "Дом", "Здоровье"] {
                if let category = settings.addCategory(named: name) {
                    ids.append(category.id)
                }
            }
        }
        let byTitle = ["Позвонить поставщику": ids[0], "Купить хлеб и молоко": ids[1], "Выпить витамины": ids[2]]
        var reminders = SampleData.reminders.map { reminder -> Reminder in
            var copy = reminder
            copy.category = byTitle[reminder.title]
            return copy
        }
        let report = Reminder(title: "Отправить отчёт", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 17, minute: 0), timeZone: "Asia/Tashkent"), createdAt: SampleData.now, category: ids[0])
        let anna = Reminder(title: "День рождения: Анна Смирнова", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 12), time: LocalTime(hour: 10, minute: 0), rule: .yearly(month: 10, day: 12), timeZone: "Asia/Tashkent"), preAlerts: [1_440], createdAt: SampleData.now, birthday: BirthdayNote(name: "Анна Смирнова", year: 1996))
        let mom = Reminder(title: "День рождения: Мама", schedule: Schedule(start: LocalDate(year: 2027, month: 1, day: 3), time: LocalTime(hour: 10, minute: 0), rule: .yearly(month: 1, day: 3), timeZone: "Asia/Tashkent"), createdAt: SampleData.now)
        reminders += [report, anna, mom]
        store.seed(reminders: reminders, places: SampleData.places, sounds: [])
        let home = HomeContent.make(reminders: reminders, places: SampleData.places, now: SampleData.now, calendar: calendar, locale: locale, categories: store.settings.categories ?? [])
        try render(HomeScreen(content: home), name: "T-Home", style: .light)
        let panel = ZStack(alignment: .leading) {
            HomeScreen(content: home)
            Color.black.opacity(0.38)
                .ignoresSafeArea()
            SidePanel(store: store, now: SampleData.now, calendar: calendar, locale: locale, onCategory: { _ in }, onEditCategories: {}, onFriends: {}, onPlaces: {}, onBirthdays: {}, onSettings: {})
                .frame(maxWidth: 340, maxHeight: .infinity)
                .background {
                    UnevenRoundedRectangle(bottomTrailingRadius: 28, topTrailingRadius: 28, style: .circular)
                        .fill(Palette.background)
                        .ignoresSafeArea()
                }
                .padding(.trailing, 56)
        }
        try render(panel, name: "T-Panel", style: .light)
        try render(panel, name: "T-Panel-Dark", style: .dark)
        try render(CategoryScreen(store: store, categoryID: ids[0], now: SampleData.now, calendar: calendar, locale: locale, onOpen: { _ in }, onCompose: {}, onBack: {}), name: "T-Category", style: .light)
        try render(CategoriesScreen(store: store, onBack: {}), name: "T-Categories", style: .light)
        let call = reminders.first { $0.title == "Позвонить поставщику" } ?? SampleData.server
        try render(EditorScreen(draft: call, isNew: false, store: store, now: SampleData.now, calendar: calendar, locale: locale, onClose: {}), name: "T-Editor", style: .light)
        try render(BirthdayListScreen(store: store, now: SampleData.now, calendar: calendar, locale: locale, onOpen: { _ in }, onImport: {}, onBack: {}), name: "T-Birthdays", style: .light)
        try render(BirthdayAddSheet(store: store, now: SampleData.now, calendar: calendar, locale: locale, onClose: {}), name: "T-BirthdayAdd", style: .light)
    }

    func testPriorities() throws {
        try render(HomeScreen(content: SampleData.home, prioritiesPrompt: true), name: "L-TopCard", style: .light)
        let store = sampleStore()
        store.update { $0.priorities = SampleData.priorities }
        try render(PrioritiesSheet(store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onClose: {}), name: "L-TopSheet", style: .light)
        store.update { $0.priorities = SampleData.fullPriorities }
        try render(PrioritiesSheet(store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onClose: {}), name: "L-TopSheet-Full", style: .light)
        let home = HomeContent.make(reminders: SampleData.reminders, places: SampleData.places, now: SampleData.now, calendar: SampleData.calendar, locale: russian, priorities: SampleData.priorityIDs)
        try render(HomeScreen(content: home), name: "L-TopHome", style: .light)
        try render(HomeScreen(content: home), name: "L-TopHome-Dark", style: .dark)
    }

    func testPills() throws {
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let reminders = SampleData.reminders + SampleData.pillReminders
        store.seed(reminders: reminders, places: SampleData.places, sounds: [SampleData.gong, SampleData.eveningNote])
        store.update { $0.courses = [SampleData.pillCourse] }
        let home = HomeContent.make(reminders: reminders, places: SampleData.places, now: SampleData.now, calendar: SampleData.calendar, locale: russian, courses: [SampleData.pillCourse])
        let alert = PillsAlert(courseID: SampleData.pillCourse.id, title: "Пить таблетки", forecast: SampleData.pillForecast)
        try render(HomeScreen(content: home, pills: alert), name: "M-PillsHome", style: .light, height: 1150)
        try render(HomeScreen(content: home, pills: alert), name: "M-PillsHome-Dark", style: .dark, height: 1150)
        try render(EditorScreen(draft: SampleData.pillReminders[1], isNew: false, store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onClose: {}), name: "M-PillsEditor", style: .light, height: 1000)
        try render(PillsSheet(reminder: SampleData.pillReminders[1], course: SampleData.pillCourse, store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onDone: { _ in }), name: "M-PillsSheet", style: .light)
        try render(BoughtSheet(course: SampleData.pillCourse, store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onDone: { _ in }), name: "M-PillsBought", style: .light, height: 520)
    }

    @MainActor
    func testVoiceNote() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        let recording = VoiceRecordSheet(title: "Купить хлеб", recorder: VoiceRecorder(file: file, elapsed: 7, levels: SampleData.voiceLevels), onDone: { _ in })
        try render(recording, name: "M-VoiceRecord", style: .light)
        try render(recording, name: "M-VoiceRecord-Dark", style: .dark)
        let bread = SampleData.reminders[2]
        let player = VoicePlayerSheet(reminder: bread, note: SampleData.breadNote, occurrence: SampleData.now.addingTimeInterval(5 * 3600 + 600), now: SampleData.now, calendar: SampleData.calendar, locale: russian, levels: SampleData.voiceLevels, onSnooze: {}, onDone: {})
        try render(player, name: "M-VoicePlay", style: .light, height: 520)
        try render(player, name: "M-VoicePlay-Dark", style: .dark, height: 520)
    }

    @MainActor
    func testDiscussion() throws {
        let locale = Locale(identifier: "ru_RU")
        func at(_ hour: Int, _ minute: Int) -> Int64 {
            let date = SampleData.calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: hour, minute: minute)) ?? SampleData.now
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        var movie = Reminder(title: "Кино в субботу", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 10), time: LocalTime(hour: 19, minute: 0), timeZone: "Asia/Tashkent"), createdAt: SampleData.now)
        movie.shared = SharedInfo(owner: SharedPerson(id: "anna", name: "Аня"), status: SharedStatus.accepted, members: [
            SharedMember(id: "ilya", name: "Илья", status: SharedStatus.accepted),
            SharedMember(id: "me", name: "Саша", status: SharedStatus.accepted),
        ], doneMode: .each)
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        store.seed(reminders: [movie], places: [], sounds: [])
        let comments = [
            SharedComment(id: "c1", author: "anna", text: "Билеты купила, ряд 7, места 12–14", at: at(18, 2), seq: 1),
            SharedComment(id: "c2", author: "ilya", text: "Опоздаю минут на 10, начинайте без меня", at: at(18, 40), seq: 2),
            SharedComment(id: "c3", author: "me", text: "Возьму попкорн на всех", at: at(18, 41), seq: 3),
        ]
        let detail = SharedDetailScreen(store: store, reminderID: movie.id, now: SampleData.now, calendar: SampleData.calendar, locale: locale, comments: comments, me: "me", onEdit: {}, onClose: {})
        try render(detail, name: "P-Comments", style: .light, height: 1400)
        try render(detail, name: "P-Comments-Dark", style: .dark, height: 1400)

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let events = [
            BellService.Event(id: "e1", kind: "comment", actor: "anna", actorName: "Аня", item: movie.id.uuidString, title: "Кино в субботу", at: now - 5 * 60_000, text: "Билеты купила, ряд 7, места 12–14"),
            BellService.Event(id: "e2", kind: "ticked", actor: "ilya", actorName: "Илья", item: UUID().uuidString, title: "Купить подарок маме", at: now - 60 * 60_000),
            BellService.Event(id: "e3", kind: "thanks", actor: "mom", actorName: "Мама", item: UUID().uuidString, title: "Полить цветы", at: now - 26 * 3_600_000),
            BellService.Event(id: "e4", kind: "ticked", actor: "ilya", actorName: "Илья", item: UUID().uuidString, title: "Забрать посылку", at: now - 50 * 3_600_000),
        ]
        UserDefaults.standard.set(["e4"], forKey: "bell.thanked")
        defer { UserDefaults.standard.removeObject(forKey: "bell.thanked") }
        let bell = BellScreen(bell: BellService(events: events, seen: [events[2].mark, events[3].mark]), onEvent: { _ in }, onNews: { _ in }, onBack: {})
        try render(bell, name: "P-Bell", style: .light)
        try render(bell, name: "P-Bell-Dark", style: .dark)
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
        try render(SettingsScreen(store: sampleStore(), locale: russian, onBack: {}), name: "D-Settings", style: .light, height: 2800)
    }

    func testIcon() throws {
        try render(IconScreen(onBack: {}), name: "L-IconPicker", style: .light)
        try render(IconScreen(onBack: {}), name: "L-IconPicker-Dark", style: .dark)
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

    @MainActor
    func testBell() throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let events = [
            BellService.Event(id: "e1", kind: "new", actor: "a1", actorName: "Аня", item: "", title: "Кино в субботу", at: now - 5 * 60_000),
            BellService.Event(id: "e2", kind: "ticked", actor: "a2", actorName: "Илья", item: "", title: "Купить подарок маме", at: now - 70 * 60_000),
            BellService.Event(id: "e3", kind: "accepted", actor: "a3", actorName: "Мама", item: "", title: "Полить цветы", at: now - 26 * 3_600_000),
            BellService.Event(id: "e4", kind: "unfriended", actor: "a4", actorName: "Сардор", item: "", title: "", at: now - 50 * 3_600_000),
        ]
        let read: Set<String> = [events[2].mark, events[3].mark]
        try render(BellScreen(bell: BellService(events: events, seen: read), onEvent: { _ in }, onNews: { _ in }, onBack: {}), name: "K-Bell", style: .light)
        try render(BellScreen(bell: BellService(events: events, seen: read), onEvent: { _ in }, onNews: { _ in }, onBack: {}), name: "K-Bell-Dark", style: .dark)
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
        try render(ScheduledScreen(content: content, done: done, store: sampleStore(), onBack: {}, tab: .done), name: "D-History", style: .dark, height: 1400)
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
