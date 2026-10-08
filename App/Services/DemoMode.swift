#if DEBUG
import Foundation
import RemaCore

// The app as it is filmed for the store pages and social networks: its own reminders and friends, no server, no system prompts.
// Only a debug build launched with -RemaDemo and a language gets it.
enum DemoMode {
    static let language: AppLanguage? = argument("-RemaDemo").flatMap(AppLanguage.init(rawValue:))
    static let scene = argument("-RemaDemoScene") ?? ""

    static var isOn: Bool {
        language != nil
    }

    private static func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    @MainActor
    static func prepare() {
        guard let language else { return }
        AppLanguage.choose(language)
        UserDefaults.standard.set(true, forKey: RootNavigation.welcomeKey)
        UserDefaults.standard.set(true, forKey: RootNavigation.introKey)
        for tip in [Tip.friends, .voice, .widget, .place, .weather] {
            TipCenter.shared.dismiss(tip)
        }
        let english = language == .english
        Account.shared.useDemo(name: english ? "Alex" : "Саша")
        SharedService.shared.useDemo(friends: [
            SharedService.Friend(id: "anna", name: english ? "Anna" : "Аня", since: Date()),
            SharedService.Friend(id: "ilya", name: english ? "Ilya" : "Илья", since: Date()),
            SharedService.Friend(id: "mom", name: english ? "Mom" : "Мама", since: Date()),
            SharedService.Friend(id: "tim", name: english ? "Tim" : "Тимур", since: Date()),
        ], myName: english ? "Alex" : "Саша")
        Store.shared.seed(reminders: reminders(english: english), places: [], sounds: [])
    }

    private static func reminders(english: Bool) -> [Reminder] {
        let calendar = Calendar.current
        let now = Date()
        let zone = TimeZone.current.identifier
        func day(_ offset: Int) -> LocalDate {
            let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return LocalDate(year: parts.year ?? 2026, month: parts.month ?? 1, day: parts.day ?? 1)
        }
        // The day is laid out from the hour of the recording, so the dial always has what is still ahead.
        let hour = calendar.component(.hour, from: now)
        let minutes = hour * 60 + calendar.component(.minute, from: now) + 40
        let call = LocalTime(hour: min(23, minutes / 60), minute: (minutes % 60) / 5 * 5)
        func later(_ hours: Int, _ minute: Int = 0) -> LocalTime {
            LocalTime(hour: min(23, hour + hours), minute: minute)
        }
        let morning = LocalTime(hour: max(7, min(hour - 3, 9)), minute: 0)

        var vitamins = Reminder(title: english ? "Take vitamins" : "Выпить витамины", schedule: Schedule(start: day(-7), time: morning, rule: .daily), nag: true, createdAt: now)
        vitamins.completedThrough = calendar.date(bySettingHour: morning.hour, minute: 0, second: 0, of: now)

        let anniversary = calendar.dateComponents([.month, .day], from: calendar.date(byAdding: .day, value: 17, to: now) ?? now)
        var movie = Reminder(title: english ? "Movie night" : "Кино с друзьями", schedule: Schedule(start: day(0), time: later(3), timeZone: zone), createdAt: now)
        movie.shared = SharedInfo(owner: SharedPerson(id: "demo", name: english ? "Alex" : "Саша"), status: SharedStatus.owner, members: [
            SharedMember(id: "anna", name: english ? "Anna" : "Аня", status: SharedStatus.accepted),
            SharedMember(id: "ilya", name: english ? "Ilya" : "Илья", status: SharedStatus.accepted),
            SharedMember(id: "mom", name: english ? "Mom" : "Мама", status: SharedStatus.invited),
        ], doneMode: .each, seq: 1)

        var result = [
            vitamins,
            Reminder(title: english ? "Call the supplier" : "Позвонить поставщику", schedule: Schedule(start: day(0), time: call), preAlerts: [15], urgent: true, createdAt: now),
            Reminder(title: english ? "Buy bread and milk" : "Купить хлеб и молоко", schedule: Schedule(start: day(0), time: later(2)), createdAt: now),
            movie,
            Reminder(title: english ? "Water the plants" : "Полить цветы", schedule: Schedule(start: day(0), time: later(4, 30), rule: .daily), createdAt: now),
            Reminder(title: english ? "Dentist" : "Стоматолог", schedule: Schedule(start: day(9), time: LocalTime(hour: 15, minute: 0)), preAlerts: [1_440], createdAt: now),
            Reminder(title: english ? "Mom's birthday" : "День рождения мамы", schedule: Schedule(start: day(17), time: LocalTime(hour: 9, minute: 0), rule: .yearly(month: anniversary.month ?? 1, day: anniversary.day ?? 1)), createdAt: now),
        ]
        // The friends scene starts with an invitation from a friend waiting on the main screen.
        if scene == "friends" {
            let saturday = (7 - calendar.component(.weekday, from: now)) % 7
            var games = Reminder(title: english ? "Board games on Saturday" : "Настолки в субботу", schedule: Schedule(start: day(saturday == 0 ? 7 : saturday), time: LocalTime(hour: 18, minute: 0), timeZone: zone), createdAt: now)
            games.shared = SharedInfo(owner: SharedPerson(id: "ilya", name: english ? "Ilya" : "Илья"), status: SharedStatus.invited, members: [
                SharedMember(id: "demo", name: english ? "Alex" : "Саша", status: SharedStatus.invited),
                SharedMember(id: "anna", name: english ? "Anna" : "Аня", status: SharedStatus.accepted),
            ], doneMode: .each, seq: 1)
            result.append(games)
        }
        return result
    }
}
#endif
