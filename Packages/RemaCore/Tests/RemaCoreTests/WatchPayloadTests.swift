import Foundation
import Testing
@testable import RemaCore

struct WatchPayloadTests {
    let calendar = PhraseParserTests.calendar
    let now = PhraseParserTests.now

    func reminder(_ title: String, day: Int, hour: Int, minute: Int = 0) -> Reminder {
        Reminder(title: title, schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: day), time: LocalTime(hour: hour, minute: minute)), createdAt: now)
    }

    @Test func todayAndTomorrowWithNext() throws {
        var vitamins = reminder("Витамины", day: 5, hour: 9)
        vitamins.completedThrough = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))
        let call = reminder("Позвонить", day: 5, hour: 14, minute: 30)
        let server = reminder("Сервер", day: 6, hour: 10)
        let later = reminder("Потом", day: 9, hour: 10)
        let payload = WatchPayload.make(reminders: [vitamins, call, server, later], now: now, calendar: calendar)
        #expect(payload.items.map(\.title) == ["Витамины", "Позвонить", "Сервер"])
        #expect(payload.today(now, calendar: calendar).count == 2)
        #expect(payload.next(after: now)?.title == "Позвонить")
        #expect(payload.items.first?.done == true)
    }

    @Test func roundTripsThroughJSON() throws {
        let payload = WatchPayload.make(reminders: [reminder("Позвонить", day: 5, hour: 14, minute: 30)], now: now, calendar: calendar)
        let data = try JSONEncoder().encode(payload)
        #expect(try JSONDecoder().decode(WatchPayload.self, from: data) == payload)
    }
}
