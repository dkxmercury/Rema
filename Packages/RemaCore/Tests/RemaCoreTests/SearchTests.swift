import Foundation
import Testing
@testable import RemaCore

struct SearchTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        return calendar
    }()

    let locale = Locale(identifier: "ru_RU")

    func moment(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    var now: Date {
        moment(4, 9, 5)
    }

    func once(_ title: String, day: Int, hour: Int = 19) -> Reminder {
        Reminder(title: title, schedule: Schedule(start: LocalDate(year: 2026, month: 11, day: day), time: LocalTime(hour: hour, minute: 0)), createdAt: moment(1, 0, 0))
    }

    func find(_ query: String, _ reminders: [Reminder], places: [Place] = [], people: @escaping (Reminder) -> [String] = { _ in [] }) -> SearchResults {
        ReminderSearch.find(query, in: reminders, places: places, people: people, now: now, calendar: calendar, locale: locale)
    }

    @Test func titleIgnoresCaseAndYo() {
        let found = find("елка", [once("Ёлка во дворе", day: 10)])
        #expect(found.upcoming.map(\.field) == [.title])
        #expect(found.upcoming.first?.date == moment(10, 19, 0))
    }

    @Test func itemOfTheList() {
        var groceries = once("Купить продукты", day: 5)
        groceries.items = [ChecklistItem(text: "Молоко 2 л"), ChecklistItem(text: "Торт для Саши")]
        #expect(find("саш", [groceries]).upcoming.map(\.field) == [.item("Торт для Саши")])
    }

    @Test func placeAndPerson() {
        let place = Place(name: "У Саши", icon: "home", latitude: 41.3, longitude: 69.25, radius: 150, createdAt: moment(1, 0, 0))
        let books = Reminder(title: "Отвезти книги", schedule: nil, placeIDs: [place.id], createdAt: moment(1, 0, 0))
        let movie = once("Кино в субботу", day: 7)
        let found = find("саш", [books, movie], places: [place], people: { $0.id == movie.id ? ["Илья", "Саша"] : [] })
        #expect(found.upcoming.map(\.field) == [.person("Саша"), .place("У Саши")])
        #expect(found.upcoming.last?.date == nil)
    }

    @Test func titleComesBeforeTheList() {
        var gift = once("Подарок для Саши", day: 6)
        gift.items = [ChecklistItem(text: "Открытка Саше")]
        #expect(find("саш", [gift]).upcoming.map(\.field) == [.title])
    }

    @Test func doneOnceGoesEarlierAndRepeatGoesAhead() {
        var gift = once("Подарок для Саши", day: 2, hour: 18)
        gift.markDone(through: moment(2, 18, 0))
        let school = Reminder(title: "Забрать Сашу из школы", schedule: Schedule(start: LocalDate(year: 2026, month: 11, day: 2), time: LocalTime(hour: 15, minute: 30), rule: .weekdays), createdAt: moment(1, 0, 0))
        let found = find("саш", [gift, school])
        #expect(found.upcoming.map(\.reminderID) == [school.id])
        #expect(found.upcoming.first?.date == moment(4, 15, 30))
        #expect(found.earlier.map(\.reminderID) == [gift.id])
        #expect(found.earlier.first?.done == true)
        #expect(found.count == 2)
    }

    @Test func skipsDeletedAndUnansweredInvitations() {
        var deleted = once("Позвонить Саше", day: 6)
        deleted.deletedAt = moment(3, 0, 0)
        var invitation = once("Саша зовёт в кино", day: 7)
        invitation.shared = SharedInfo(owner: SharedPerson(id: "f1", name: "Саша"), status: SharedStatus.invited, members: [], doneMode: .each)
        #expect(find("саш", [deleted, invitation]).count == 0)
    }

    @Test func blankQueryFindsNothing() {
        #expect(find("  ", [once("Позвонить Саше", day: 6)]) == .empty)
    }

    @Test func aLongRepeatOverYearsAgoShowsItsRealLastTime() throws {
        let start = LocalDate(year: 2020, month: 1, day: 1)
        let until = Reminder(title: "Таблетки старые", schedule: Schedule(start: start, time: LocalTime(hour: 19, minute: 0), rule: .daily, end: .until(LocalDate(year: 2023, month: 6, day: 30))), createdAt: moment(1, 0, 0))
        let counted = Reminder(title: "Таблетки по счёту", schedule: Schedule(start: start, time: LocalTime(hour: 19, minute: 0), rule: .daily, end: .count(1500)), createdAt: moment(1, 0, 0))
        let found = find("таблетки", [until, counted])
        #expect(found.upcoming.isEmpty)
        let first = try #require(calendar.date(from: DateComponents(year: 2020, month: 1, day: 1, hour: 19)))
        let byCount = try #require(calendar.date(byAdding: .day, value: 1499, to: first))
        let byDate = try #require(calendar.date(from: DateComponents(year: 2023, month: 6, day: 30, hour: 19)))
        #expect(Set(found.earlier.compactMap(\.date)) == [byCount, byDate])
    }
}
