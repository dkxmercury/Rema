import Foundation
import Testing
@testable import RemaCore

struct AgendaTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        return calendar
    }()

    func moment(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    var sample: [Reminder] {
        let created = moment(1, 0, 0)
        var vitamins = Reminder(title: "Выпить витамины", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 1), time: LocalTime(hour: 9, minute: 0), rule: .daily), nag: true, createdAt: created)
        vitamins.completedThrough = moment(5, 9, 0)
        let call = Reminder(title: "Позвонить поставщику", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 14, minute: 30)), preAlerts: [15], urgent: true, createdAt: created)
        let bread = Reminder(title: "Купить хлеб и молоко", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 19, minute: 0)), createdAt: created)
        let flowers = Reminder(title: "Полить цветы", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 1), time: LocalTime(hour: 21, minute: 30), rule: .weekly([.monday, .thursday])), createdAt: created)
        let server = Reminder(title: "Оплатить сервер", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 6), time: LocalTime(hour: 10, minute: 0), rule: .yearly(month: 10, day: 6)), createdAt: created)
        return [vitamins, call, bread, flowers, server]
    }

    @Test func todayMatchesTheHomeMockup() {
        let reminders = sample
        let today = Agenda.day(moment(5, 13, 50), reminders: reminders, calendar: calendar)
        let titles = today.compactMap { item in reminders.first { $0.id == item.reminderID }?.title }
        #expect(titles == ["Выпить витамины", "Позвонить поставщику", "Купить хлеб и молоко", "Полить цветы"])
        #expect(today.map(\.done) == [true, false, false, false])
    }

    @Test func upcomingSkipsDoneAndPast() {
        let reminders = sample
        let next = Agenda.upcoming(after: moment(5, 13, 50), reminders: reminders, calendar: calendar)
        let first = reminders.first { $0.id == next.first?.reminderID }
        #expect(first?.title == "Позвонить поставщику")
        #expect(next.first?.occurrence == moment(5, 14, 30))
        let vitamins = next.first { item in reminders.first { $0.id == item.reminderID }?.title == "Выпить витамины" }
        #expect(vitamins?.occurrence == moment(6, 9, 0))
    }

    @Test func tomorrowHasTheServerPayment() {
        let reminders = sample
        let tomorrow = Agenda.day(moment(6, 8, 0), reminders: reminders, calendar: calendar)
        let titles = tomorrow.compactMap { item in reminders.first { $0.id == item.reminderID }?.title }
        #expect(titles == ["Выпить витамины", "Оплатить сервер"])
    }

    @Test func missedAreThePastOnesWithoutATick() {
        var reminders = sample
        let missed = Agenda.missed(moment(5, 15, 0), reminders: reminders, calendar: calendar)
        let titles = missed.compactMap { item in reminders.first { $0.id == item.reminderID }?.title }
        #expect(titles == ["Позвонить поставщику"])
        reminders[1].snoozedUntil = moment(5, 16, 0)
        #expect(Agenda.missed(moment(5, 15, 0), reminders: reminders, calendar: calendar).isEmpty)
        #expect(Agenda.missed(moment(5, 14, 30), reminders: sample, calendar: calendar).isEmpty)
    }
}
