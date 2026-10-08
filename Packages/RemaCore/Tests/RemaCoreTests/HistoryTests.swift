import Foundation
import Testing
@testable import RemaCore

struct HistoryTests {
    let calendar = PhraseParserTests.calendar
    let now = PhraseParserTests.now

    func moment(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func daily(at hour: Int, _ minute: Int = 0) -> Reminder {
        Reminder(title: "Выпить витамины", schedule: Schedule(start: LocalDate(year: 2026, month: 9, day: 1), time: LocalTime(hour: hour, minute: minute), rule: .daily), createdAt: moment(9, 1, 0, 0))
    }

    @Test func dailyStreakCountsToday() {
        var vitamins = daily(at: 9)
        for day in 24...30 {
            vitamins.markDone(through: moment(9, day, 9, 0), at: moment(9, day, 9, 2))
        }
        for day in 1...5 {
            vitamins.markDone(through: moment(10, day, 9, 0), at: moment(10, day, 9, 2))
        }
        let streak = History.streaks([vitamins], now: now, calendar: calendar).first
        #expect(streak?.count == 12)
        #expect(streak?.daily == true)
        #expect(streak?.recent == Array(repeating: true, count: 7))
    }

    @Test func timeStillAheadTodayDoesNotBreak() {
        var evening = daily(at: 21)
        for day in 1...4 {
            evening.markDone(through: moment(10, day, 21, 0), at: moment(10, day, 21, 5))
        }
        #expect(History.streaks([evening], now: now, calendar: calendar).first?.count == 4)
        var missed = daily(at: 21)
        for day in [1, 2, 4] {
            missed.markDone(through: moment(10, day, 21, 0), at: moment(10, day, 21, 5))
        }
        #expect(History.streaks([missed], now: now, calendar: calendar).isEmpty)
    }

    @Test func snoozedTickCountsForItsOccurrence() {
        var flowers = Reminder(title: "Полить цветы", schedule: Schedule(start: LocalDate(year: 2026, month: 9, day: 1), time: LocalTime(hour: 21, minute: 30), rule: .weekly([.monday, .thursday])), createdAt: moment(9, 1, 0, 0))
        for (month, day) in [(9, 21), (9, 24), (9, 28), (10, 1)] {
            flowers.markDone(through: moment(month, day, 22, 0), at: moment(month, day, 22, 0))
        }
        let streak = History.streaks([flowers], now: now, calendar: calendar).first
        #expect(streak?.count == 4)
        #expect(streak?.daily == false)
        #expect(streak?.recent.prefix(4).allSatisfy { $0 } == true)
    }

    @Test func entriesAreNewestFirst() {
        var vitamins = daily(at: 9)
        vitamins.markDone(through: moment(10, 4, 9, 0), at: moment(10, 4, 9, 0))
        vitamins.markDone(through: moment(10, 5, 9, 0), at: moment(10, 5, 9, 2))
        var deleted = daily(at: 10)
        deleted.markDone(through: moment(10, 5, 10, 0), at: moment(10, 5, 10, 1))
        deleted.deletedAt = now
        let entries = History.entries([vitamins, deleted], since: moment(10, 1, 0, 0))
        #expect(entries.map(\.at) == [moment(10, 5, 9, 2), moment(10, 4, 9, 0)])
    }

    @Test func reopenTakesTheTickBack() {
        var vitamins = daily(at: 9)
        vitamins.markDone(through: moment(10, 5, 9, 0), at: moment(10, 5, 9, 2))
        vitamins.reopen(before: moment(10, 5, 9, 0))
        #expect(vitamins.history.isEmpty)
        #expect(vitamins.completedThrough == moment(10, 5, 8, 59).addingTimeInterval(59))
    }

    @Test func historyKeepsTheNewest() {
        var vitamins = daily(at: 9)
        let start = moment(7, 1, 9, 0)
        for day in 0..<110 {
            let occurrence = start.addingTimeInterval(Double(day) * 86_400)
            vitamins.markDone(through: occurrence, at: occurrence)
        }
        #expect(vitamins.history.count == Reminder.historyLimit)
        #expect(vitamins.history.last?.occurrence == start.addingTimeInterval(109 * 86_400))
    }
}
