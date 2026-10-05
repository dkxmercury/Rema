import Foundation
import Testing
@testable import RemaCore

struct ModelsTests {
    let created = Date(timeIntervalSince1970: 1_791_100_000)

    @Test func reminderSurvivesEncoding() throws {
        let place = UUID()
        let reminder = Reminder(
            title: "Оплатить сервер",
            schedule: Schedule(
                start: LocalDate(year: 2026, month: 10, day: 6),
                time: LocalTime(hour: 10, minute: 0),
                rule: .yearly(month: 10, day: 6),
                end: .never
            ),
            preAlerts: [10_080, 1_440],
            nag: true,
            urgent: true,
            placeIDs: [place],
            placeTrigger: .leave,
            sound: .builtIn("gong"),
            createdAt: created
        )
        let data = try JSONEncoder().encode(reminder)
        let decoded = try JSONDecoder().decode(Reminder.self, from: data)
        #expect(decoded == reminder)
        #expect(decoded.updatedAt == created)
    }

    @Test func everyRepeatRuleSurvivesEncoding() throws {
        let rules: [RepeatRule] = [
            .daily,
            .weekdays,
            .weekly([.monday, .thursday]),
            .everyDays(3),
            .monthlyOnDay(6),
            .monthlyOnWeekday(ordinal: 1, weekday: .monday),
            .monthlyOnWeekday(ordinal: -1, weekday: .friday),
            .yearly(month: 2, day: 29),
        ]
        for rule in rules {
            let data = try JSONEncoder().encode(rule)
            #expect(try JSONDecoder().decode(RepeatRule.self, from: data) == rule)
        }
    }

    @Test func placeOnlyReminder() {
        let reminder = Reminder(title: "Забрать посылку", schedule: nil, placeIDs: [UUID()], placeTrigger: .leave, createdAt: created)
        #expect(reminder.isPlaceOnly)
    }

    @Test func placeRadiusIsClamped() {
        let small = Place(name: "Дом", icon: "home", latitude: 41.3, longitude: 69.2, radius: 20, createdAt: created)
        let large = Place(name: "Дача", icon: "tree", latitude: 41.3, longitude: 69.2, radius: 5000, createdAt: created)
        #expect(small.radius == 100)
        #expect(large.radius == 1000)
    }

    @Test func placesSavedBeforeOneOffPlacesStayRemembered() throws {
        let place = Place(name: "Дом", icon: "home", latitude: 41.3, longitude: 69.2, radius: 150, createdAt: created)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(place)) as? [String: Any])
        object.removeValue(forKey: "remembered")
        let old = try JSONDecoder().decode(Place.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.remembered)
        #expect(old == place)
    }

    @Test func oneOffPlaceSurvivesCoding() throws {
        let place = Place(name: "Место на карте", icon: "home", latitude: 41.3, longitude: 69.2, radius: 150, createdAt: created, remembered: false)
        let decoded = try JSONDecoder().decode(Place.self, from: JSONEncoder().encode(place))
        #expect(!decoded.remembered)
        #expect(decoded == place)
    }

    @Test func standardSettingsMatchTheMockup() {
        let settings = Settings.standard(at: created)
        #expect(settings.morning == LocalTime(hour: 9, minute: 0))
        #expect(settings.evening == LocalTime(hour: 19, minute: 0))
        #expect(settings.nagInterval == 5)
        #expect(settings.appearance == .system)
    }

    @Test func localDatesCompare() {
        #expect(LocalDate(year: 2026, month: 10, day: 5) < LocalDate(year: 2026, month: 10, day: 6))
        #expect(LocalDate(year: 2026, month: 12, day: 31) < LocalDate(year: 2027, month: 1, day: 1))
    }
}
