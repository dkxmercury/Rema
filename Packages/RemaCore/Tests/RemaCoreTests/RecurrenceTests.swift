import Foundation
import Testing
@testable import RemaCore

struct RecurrenceTests {
    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    let tashkent = RecurrenceTests.calendar("Asia/Tashkent")

    func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, in calendar: Calendar? = nil) -> Date {
        (calendar ?? tashkent).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func days(_ dates: [Date], in calendar: Calendar? = nil) -> [String] {
        dates.map { date in
            let parts = (calendar ?? tashkent).dateComponents([.year, .month, .day, .hour, .minute], from: date)
            return String(format: "%04d-%02d-%02d %02d:%02d", parts.year!, parts.month!, parts.day!, parts.hour!, parts.minute!)
        }
    }

    func schedule(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ rule: RepeatRule?, end: RepeatEnd = .never) -> Schedule {
        Schedule(start: LocalDate(year: year, month: month, day: day), time: LocalTime(hour: hour, minute: minute), rule: rule, end: end)
    }

    @Test func onceIsSingleAndOnlyInTheFuture() {
        let once = schedule(2026, 10, 6, 10, 0, nil)
        #expect(days(Recurrence.next(once, after: moment(2026, 10, 5, 13, 50), limit: 5, calendar: tashkent)) == ["2026-10-06 10:00"])
        #expect(Recurrence.next(once, after: moment(2026, 10, 6, 10, 0), limit: 5, calendar: tashkent).isEmpty)
    }

    @Test func dailySkipsTodayWhenTimePassed() {
        let daily = schedule(2026, 10, 1, 9, 0, .daily)
        #expect(days(Recurrence.next(daily, after: moment(2026, 10, 5, 13, 50), limit: 3, calendar: tashkent)) == [
            "2026-10-06 09:00", "2026-10-07 09:00", "2026-10-08 09:00",
        ])
    }

    @Test func weekdaysJumpOverTheWeekend() {
        let weekdays = schedule(2026, 10, 1, 8, 30, .weekdays)
        #expect(days(Recurrence.next(weekdays, after: moment(2026, 10, 9, 20, 0), limit: 2, calendar: tashkent)) == [
            "2026-10-12 08:30", "2026-10-13 08:30",
        ])
    }

    @Test func selectedWeekdays() {
        let flowers = schedule(2026, 10, 5, 21, 30, .weekly([.monday, .thursday]))
        #expect(days(Recurrence.next(flowers, after: moment(2026, 10, 5, 13, 50), limit: 4, calendar: tashkent)) == [
            "2026-10-05 21:30", "2026-10-08 21:30", "2026-10-12 21:30", "2026-10-15 21:30",
        ])
    }

    @Test func everyThreeDays() {
        let rule = schedule(2026, 10, 5, 12, 0, .everyDays(3))
        #expect(days(Recurrence.next(rule, after: moment(2026, 10, 5, 13, 0), limit: 3, calendar: tashkent)) == [
            "2026-10-08 12:00", "2026-10-11 12:00", "2026-10-14 12:00",
        ])
    }

    @Test func monthlyOnTheThirtyFirstFallsBackToTheLastDay() {
        let rent = schedule(2026, 10, 31, 10, 0, .monthlyOnDay(31))
        #expect(days(Recurrence.next(rent, after: moment(2026, 10, 1), limit: 5, calendar: tashkent)) == [
            "2026-10-31 10:00", "2026-11-30 10:00", "2026-12-31 10:00", "2027-01-31 10:00", "2027-02-28 10:00",
        ])
    }

    @Test func firstMondayAndLastFriday() {
        let first = schedule(2026, 10, 5, 9, 0, .monthlyOnWeekday(ordinal: 1, weekday: .monday))
        #expect(days(Recurrence.next(first, after: moment(2026, 10, 5, 10, 0), limit: 2, calendar: tashkent)) == [
            "2026-11-02 09:00", "2026-12-07 09:00",
        ])
        let last = schedule(2026, 10, 1, 18, 0, .monthlyOnWeekday(ordinal: -1, weekday: .friday))
        #expect(days(Recurrence.next(last, after: moment(2026, 10, 1), limit: 2, calendar: tashkent)) == [
            "2026-10-30 18:00", "2026-11-27 18:00",
        ])
    }

    @Test func yearlyLeapDay() {
        let birthday = schedule(2027, 1, 1, 9, 0, .yearly(month: 2, day: 29))
        #expect(days(Recurrence.next(birthday, after: moment(2027, 1, 1), limit: 3, calendar: tashkent)) == [
            "2027-02-28 09:00", "2028-02-29 09:00", "2029-02-28 09:00",
        ])
    }

    @Test func yearlyServerPayment() {
        let payment = schedule(2026, 10, 6, 10, 0, .yearly(month: 10, day: 6))
        #expect(days(Recurrence.next(payment, after: moment(2026, 10, 5, 13, 50), limit: 3, calendar: tashkent)) == [
            "2026-10-06 10:00", "2027-10-06 10:00", "2028-10-06 10:00",
        ])
    }

    @Test func endsAfterCount() {
        let three = schedule(2026, 10, 5, 9, 0, .daily, end: .count(3))
        #expect(days(Recurrence.next(three, after: moment(2026, 10, 5, 10, 0), limit: 10, calendar: tashkent)) == [
            "2026-10-06 09:00", "2026-10-07 09:00",
        ])
    }

    @Test func endsOnDateInclusive() {
        let until = schedule(2026, 10, 5, 9, 0, .daily, end: .until(LocalDate(year: 2026, month: 10, day: 7)))
        #expect(days(Recurrence.next(until, after: moment(2026, 10, 5), limit: 10, calendar: tashkent)) == [
            "2026-10-05 09:00", "2026-10-06 09:00", "2026-10-07 09:00",
        ])
    }

    @Test func localTimeStaysLocalAcrossDaylightSaving() {
        let berlin = RecurrenceTests.calendar("Europe/Berlin")
        let daily = schedule(2027, 3, 26, 9, 0, .daily)
        let result = Recurrence.next(daily, after: moment(2027, 3, 26, in: berlin), limit: 4, calendar: berlin)
        #expect(days(result, in: berlin) == ["2027-03-26 09:00", "2027-03-27 09:00", "2027-03-28 09:00", "2027-03-29 09:00"])
        #expect(result[2].timeIntervalSince(result[1]) == 23 * 3600)
    }

    @Test func weekdayMapping() {
        #expect(LocalDate(year: 2026, month: 10, day: 5).weekday == .monday)
        #expect(LocalDate(year: 2026, month: 10, day: 11).weekday == .sunday)
        #expect(LocalDate.days(in: 2, year: 2028) == 29)
        #expect(LocalDate.days(in: 2, year: 2027) == 28)
    }
}
