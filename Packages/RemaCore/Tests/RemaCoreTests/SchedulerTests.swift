import Foundation
import Testing
@testable import RemaCore

struct SchedulerTests {
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

    func once(_ hour: Int, _ minute: Int, day: Int = 5) -> Schedule {
        Schedule(start: LocalDate(year: 2026, month: 10, day: day), time: LocalTime(hour: hour, minute: minute))
    }

    @Test func nagSeriesFollowsTheReminder() {
        let call = Reminder(title: "Позвонить поставщику", schedule: once(14, 30), nag: true, urgent: true, createdAt: now)
        let plan = Scheduler.plan(reminders: [call], settings: settings, now: now, calendar: calendar)
        #expect(plan.count == 1 + Scheduler.nagRepeats)
        #expect(plan.first?.fireDate == moment(2026, 10, 5, 14, 30))
        #expect(plan.first?.kind == .main)
        #expect(plan[1].fireDate == moment(2026, 10, 5, 14, 35))
        #expect(plan.last?.fireDate == moment(2026, 10, 5, 15, 30))
        #expect(plan.allSatisfy { $0.urgent })
    }

    @Test func earlyAlertsBeforeYearlyPayment() {
        let payment = Reminder(
            title: "Оплатить сервер",
            schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 6), time: LocalTime(hour: 10, minute: 0), rule: .yearly(month: 10, day: 6)),
            preAlerts: [1_440, 10_080],
            createdAt: now
        )
        let plan = Scheduler.plan(reminders: [payment], settings: settings, now: now, calendar: calendar)
        let dates = plan.map(\.fireDate)
        #expect(dates.contains(moment(2026, 10, 6, 10, 0)))
        #expect(dates.contains(moment(2026, 10, 5, 10, 0)) == false)
        #expect(dates.contains(moment(2027, 9, 29, 10, 0)))
        #expect(dates.contains(moment(2027, 10, 5, 10, 0)))
        #expect(dates.contains(moment(2027, 10, 6, 10, 0)))
        #expect(dates == dates.sorted())
    }

    @Test func completedOccurrenceIsSkipped() {
        var vitamins = Reminder(
            title: "Выпить витамины",
            schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 1), time: LocalTime(hour: 15, minute: 0), rule: .daily),
            createdAt: now
        )
        vitamins.completedThrough = moment(2026, 10, 5, 15, 0)
        let plan = Scheduler.plan(reminders: [vitamins], settings: settings, now: now, calendar: calendar)
        #expect(plan.first?.fireDate == moment(2026, 10, 6, 15, 0))
    }

    @Test func pastOccurrenceKeepsNaggingUntilDone() {
        let pills = Reminder(title: "Таблетка", schedule: once(13, 30), nag: true, createdAt: now)
        let plan = Scheduler.plan(reminders: [pills], settings: settings, now: now, calendar: calendar)
        #expect(plan.first?.fireDate == moment(2026, 10, 5, 13, 55))
        #expect(plan.allSatisfy { $0.kind != .main })
    }

    @Test func snoozeReplacesThePastOccurrence() {
        var pills = Reminder(title: "Таблетка", schedule: once(13, 30), nag: true, createdAt: now)
        pills.snoozedUntil = moment(2026, 10, 5, 14, 5)
        let plan = Scheduler.plan(reminders: [pills], settings: settings, now: now, calendar: calendar)
        #expect(plan.first?.kind == .snoozed)
        #expect(plan.first?.fireDate == moment(2026, 10, 5, 14, 5))
        #expect(plan.contains { $0.fireDate == moment(2026, 10, 5, 13, 55) } == false)
    }

    @Test func placeOnlyAndDeletedPlanNothing() {
        let parcel = Reminder(title: "Забрать посылку", schedule: nil, placeIDs: [UUID()], placeTrigger: .leave, createdAt: now)
        let gone = Reminder(title: "Старое", schedule: once(18, 0), createdAt: now, deletedAt: now)
        #expect(Scheduler.plan(reminders: [parcel, gone], settings: settings, now: now, calendar: calendar).isEmpty)
    }

    @Test func capacityKeepsTheNearest() {
        let many = (0..<30).map { index in
            Reminder(title: "Пункт \(index)", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 6), time: LocalTime(hour: 9, minute: 0), rule: .daily), createdAt: now)
        }
        let plan = Scheduler.plan(reminders: many, settings: settings, now: now, calendar: calendar)
        #expect(plan.count == Scheduler.capacity)
        #expect(plan.first?.fireDate == moment(2026, 10, 6, 9, 0))
        #expect(plan.last!.fireDate <= moment(2026, 10, 7, 9, 0))
    }

    @Test func identifiersRoundTrip() {
        let id = UUID()
        let value = Scheduler.identifier(id, occurrence: now, kind: .nag(index: 3))
        #expect(Scheduler.reminderID(fromIdentifier: value) == id)
        #expect(value.hasSuffix(".nag3"))
    }

    @Test func followUpComesAfterAMissedOccurrence() {
        let call = Reminder(title: "Позвонить маме", schedule: once(13, 40), createdAt: now)
        let plan = Scheduler.plan(reminders: [call], settings: settings, now: now, calendar: calendar, followUp: 30)
        #expect(plan.map(\.kind) == [.missed])
        #expect(plan.first?.fireDate == moment(2026, 10, 5, 14, 10))
        #expect(plan.first?.occurrence == moment(2026, 10, 5, 13, 40))
    }

    @Test func followUpSkipsDoneAndNaggingReminders() {
        var done = Reminder(title: "Позвонить маме", schedule: once(13, 40), createdAt: now)
        done.completedThrough = moment(2026, 10, 5, 13, 40)
        let nag = Reminder(title: "Таблетка", schedule: once(14, 0), nag: true, createdAt: now)
        let plan = Scheduler.plan(reminders: [done, nag], settings: settings, now: now, calendar: calendar, followUp: 30)
        #expect(plan.contains { $0.kind == .missed } == false)
        #expect(Scheduler.plan(reminders: [done], settings: settings, now: now, calendar: calendar).isEmpty)
    }

    @Test func remindersAheadComeBeforeFarRepeats() {
        let daily = Schedule(start: LocalDate(year: 2026, month: 10, day: 6), time: LocalTime(hour: 9, minute: 0), rule: .daily)
        let pills = Reminder(title: "Таблетки", schedule: daily, nag: true, createdAt: now)
        let water = Reminder(title: "Вода", schedule: daily, nag: true, createdAt: now)
        let dentist = Reminder(title: "Стоматолог", schedule: once(10, 0, day: 9), createdAt: now)
        let plan = Scheduler.plan(reminders: [pills, water, dentist], settings: settings, now: now, calendar: calendar)
        #expect(plan.count == Scheduler.capacity)
        #expect(plan.contains { $0.reminderID == dentist.id && $0.kind == .main })
        #expect(plan.filter { $0.fireDate <= moment(2026, 10, 6, 13, 50) }.count == 2 * (1 + Scheduler.nagRepeats))
        #expect(plan == plan.sorted { $0.fireDate == $1.fireDate ? $0.identifier < $1.identifier : $0.fireDate < $1.fireDate })
    }

    @Test func morningRepeatsDoNotPushOutTheEvening() {
        let calls = [14, 15, 16].map { hour in
            Reminder(title: "Звонок \(hour)", schedule: once(hour, 0), nag: true, createdAt: now)
        }
        let dinner = Reminder(title: "Ужин", schedule: once(21, 0), createdAt: now)
        let plan = Scheduler.plan(reminders: calls + [dinner], settings: settings, now: now, calendar: calendar, capacity: 20)
        #expect(plan.count == 20)
        #expect(plan.contains { $0.reminderID == dinner.id && $0.kind == .main })
        #expect(calls.allSatisfy { call in plan.contains { $0.reminderID == call.id && $0.kind == .main } })
        #expect(plan == plan.sorted { $0.fireDate == $1.fireDate ? $0.identifier < $1.identifier : $0.fireDate < $1.fireDate })
    }

    @Test func snoozeToTheNextOccurrenceRingsOnce() {
        let daily = Schedule(start: LocalDate(year: 2026, month: 10, day: 1), time: LocalTime(hour: 9, minute: 0), rule: .daily)
        var pills = Reminder(title: "Таблетки", schedule: daily, nag: true, createdAt: now)
        pills.snoozedUntil = moment(2026, 10, 6, 9, 0)
        let plan = Scheduler.plan(reminders: [pills], settings: settings, now: now, calendar: calendar)
        #expect(plan.filter { $0.fireDate == moment(2026, 10, 6, 9, 0) }.count == 1)
        #expect(Set(plan.map(\.identifier)).count == plan.count)
    }
}
