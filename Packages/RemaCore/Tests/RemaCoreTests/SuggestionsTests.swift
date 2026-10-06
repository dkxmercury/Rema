import Foundation
import Testing
@testable import RemaCore

struct SuggestionsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        return calendar
    }()

    func moment(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func recognizesReasonsInEveryLanguage() {
        #expect(Suggestions.reason(for: "стоматолог") == .medical)
        #expect(Suggestions.reason(for: "Записаться к врачу") == .medical)
        #expect(Suggestions.reason(for: "Dentist appointment") == .medical)
        #expect(Suggestions.reason(for: "Termin beim Zahnarzt") == .medical)
        #expect(Suggestions.reason(for: "rendez-vous chez le médecin") == .medical)
        #expect(Suggestions.reason(for: "shifokorga borish") == .medical)
        #expect(Suggestions.reason(for: "موعد عند الطبيب") == .medical)
        #expect(Suggestions.reason(for: "поезд в Самарканд") == .travel)
        #expect(Suggestions.reason(for: "Flight to Istanbul") == .travel)
        #expect(Suggestions.reason(for: "vol pour Paris") == .travel)
        #expect(Suggestions.reason(for: "день рождения мамы") == .birthday)
        #expect(Suggestions.reason(for: "Geburtstag von Anna") == .birthday)
        #expect(Suggestions.reason(for: "onamning tug‘ilgan kuni") == .birthday)
        #expect(Suggestions.reason(for: "купить хлеб") == nil)
        #expect(Suggestions.reason(for: "volley training") == nil)
        #expect(Suggestions.reason(for: "garer la voiture") == nil)
    }

    @Test func suggestsADayBeforeWhenThereIsTime() {
        let now = moment(5, 13, 50)
        let suggestion = Suggestions.early(title: "стоматолог", when: moment(6, 15), preAlerts: [], now: now)
        #expect(suggestion == EarlySuggestion(minutes: 1_440, reason: .medical))
    }

    @Test func suggestsTwoHoursForTheSameDay() {
        let now = moment(5, 9)
        #expect(Suggestions.early(title: "поезд", when: moment(5, 18), preAlerts: [], now: now)?.minutes == 120)
        #expect(Suggestions.early(title: "поезд", when: moment(5, 10), preAlerts: [], now: now) == nil)
        #expect(Suggestions.early(title: "день рождения", when: moment(5, 18), preAlerts: [], now: now) == nil)
    }

    @Test func staysQuietWhenAdvanceIsAlreadySet() {
        #expect(Suggestions.early(title: "стоматолог", when: moment(8, 15), preAlerts: [60], now: moment(5, 9)) == nil)
    }

    func oneOff(_ title: String, day: Int) -> Reminder {
        Reminder(title: title, schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: day), time: LocalTime(hour: 18, minute: 0)), createdAt: moment(1, 0))
    }

    @Test func noticesThreeMondaysInARow() {
        let reminders = [oneOff("Купить корм коту", day: 5), oneOff("купить корм коту", day: 12), oneOff("Купить корм коту ", day: 19)]
        let habit = Suggestions.habit(in: reminders, now: moment(15, 9), calendar: calendar, dismissed: [])
        #expect(habit?.reminderID == reminders[2].id)
        #expect(habit?.weekday == .monday)
    }

    @Test func ignoresGapsDismissalsAndExistingRepeats() {
        let gap = [oneOff("Корм", day: 5), oneOff("Корм", day: 12), oneOff("Корм", day: 26)]
        #expect(Suggestions.habit(in: gap, now: moment(20, 9), calendar: calendar, dismissed: []) == nil)
        let row = [oneOff("Корм", day: 5), oneOff("Корм", day: 12), oneOff("Корм", day: 19)]
        let found = Suggestions.habit(in: row, now: moment(15, 9), calendar: calendar, dismissed: [])
        #expect(found != nil)
        #expect(Suggestions.habit(in: row, now: moment(15, 9), calendar: calendar, dismissed: [found!.key]) == nil)
        let weekly = Reminder(title: "Корм", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 18, minute: 0), rule: .weekly([.monday])), createdAt: moment(1, 0))
        #expect(Suggestions.habit(in: row + [weekly], now: moment(15, 9), calendar: calendar, dismissed: []) == nil)
        #expect(Suggestions.habit(in: row, now: moment(25, 9), calendar: calendar, dismissed: []) == nil)
    }
}
