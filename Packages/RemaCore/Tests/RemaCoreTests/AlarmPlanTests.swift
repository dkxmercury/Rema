import Foundation
import Testing
@testable import RemaCore

struct AlarmPlanTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        return calendar
    }()

    var now: Date { moment(2026, 10, 5, 13, 50) }
    var settings: Settings { Settings.standard(at: moment(2026, 10, 1, 0, 0)) }

    func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func persistentReminderRingsWithItsWholeSeriesButNotTheEarlyAlert() {
        let call = Reminder(title: "Позвонить поставщику", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 14, minute: 30)), preAlerts: [15], nag: true, createdAt: now)
        let rings = AlarmPlan.rings(reminders: [call], settings: settings, now: now, calendar: calendar)
        #expect(rings.count == 1 + Scheduler.nagRepeats)
        #expect(rings.first?.kind == .main)
        #expect(rings.first?.fireDate == moment(2026, 10, 5, 14, 30))
        #expect(rings.last?.fireDate == moment(2026, 10, 5, 15, 30))
        #expect(!rings.contains { $0.kind == .early(minutes: 15) })
    }

    @Test func anOrdinaryReminderStaysANotification() {
        let bread = Reminder(title: "Купить хлеб", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 19, minute: 0)), createdAt: now)
        #expect(AlarmPlan.rings(reminders: [bread], settings: settings, now: now, calendar: calendar).isEmpty)
    }

    @Test func onlyTheNextTwoDaysGetAlarms() {
        let pills = Reminder(title: "Таблетки", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 1), time: LocalTime(hour: 9, minute: 0), rule: .daily), nag: true, createdAt: now)
        let rings = AlarmPlan.rings(reminders: [pills], settings: settings, now: now, calendar: calendar)
        #expect(Set(rings.map(\.occurrence)) == [moment(2026, 10, 6, 9, 0), moment(2026, 10, 7, 9, 0)])
        #expect(rings.allSatisfy { $0.fireDate <= now.addingTimeInterval(AlarmPlan.window) })
    }

    @Test func aSnoozeRingsAgainAsAnAlarm() {
        var call = Reminder(title: "Позвонить поставщику", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 13, minute: 0)), nag: true, createdAt: now)
        call.snoozedUntil = moment(2026, 10, 5, 14, 0)
        let rings = AlarmPlan.rings(reminders: [call], settings: settings, now: now, calendar: calendar)
        #expect(rings.first?.kind == .snoozed)
        #expect(rings.first?.fireDate == moment(2026, 10, 5, 14, 0))
    }

    @Test func manyPersistentRemindersStopAtTheLimit() {
        let many = (0..<10).map { index in
            Reminder(title: "Дело \(index)", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 15, minute: index)), nag: true, createdAt: now)
        }
        let rings = AlarmPlan.rings(reminders: many, settings: settings, now: now, calendar: calendar)
        #expect(rings.count == AlarmPlan.limit)
        #expect(rings.map(\.fireDate) == rings.map(\.fireDate).sorted())
    }

    @Test func ringsTakenByAlarmsLeaveTheNotificationPlan() {
        let call = Reminder(title: "Позвонить поставщику", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 14, minute: 30)), preAlerts: [15], nag: true, createdAt: now)
        let rings = AlarmPlan.rings(reminders: [call], settings: settings, now: now, calendar: calendar)
        let plan = Scheduler.plan(reminders: [call], settings: settings, now: now, calendar: calendar, excluding: Set(rings.map(\.identifier)))
        #expect(plan.map(\.kind) == [.early(minutes: 15)])
    }
}
