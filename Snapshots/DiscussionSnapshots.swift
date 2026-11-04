import RemaCore
import SwiftUI
import XCTest
@testable import Rema

extension ScreenSnapshots {
    @MainActor
    func testDiscussion() throws {
        let locale = Locale(identifier: "ru_RU")
        func at(_ hour: Int, _ minute: Int) -> Int64 {
            let date = SampleData.calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: hour, minute: minute)) ?? SampleData.now
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        var movie = Reminder(title: "Кино в субботу", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 10), time: LocalTime(hour: 19, minute: 0), timeZone: "Asia/Tashkent"), createdAt: SampleData.now)
        movie.shared = SharedInfo(owner: SharedPerson(id: "anna", name: "Аня"), status: SharedStatus.accepted, members: [
            SharedMember(id: "ilya", name: "Илья", status: SharedStatus.accepted),
            SharedMember(id: "me", name: "Саша", status: SharedStatus.accepted),
        ], doneMode: .each)
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        store.seed(reminders: [movie], places: [], sounds: [])
        let comments = [
            SharedComment(id: "c1", author: "anna", text: "Билеты купила, ряд 7, места 12–14", at: at(18, 2), seq: 1),
            SharedComment(id: "c2", author: "ilya", text: "Опоздаю минут на 10, начинайте без меня", at: at(18, 40), seq: 2),
            SharedComment(id: "c3", author: "me", text: "Возьму попкорн на всех", at: at(18, 41), seq: 3),
        ]
        let detail = SharedDetailScreen(store: store, reminderID: movie.id, now: SampleData.now, calendar: SampleData.calendar, locale: locale, comments: comments, me: "me", onEdit: {}, onClose: {})
        try render(detail, name: "P-Comments", style: .light, height: 1400)
        try render(detail, name: "P-Comments-Dark", style: .dark, height: 1400)

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let events = [
            BellService.Event(id: "e1", kind: "comment", actor: "anna", actorName: "Аня", item: movie.id.uuidString, title: "Кино в субботу", at: now - 5 * 60_000, text: "Билеты купила, ряд 7, места 12–14"),
            BellService.Event(id: "e2", kind: "ticked", actor: "ilya", actorName: "Илья", item: UUID().uuidString, title: "Купить подарок маме", at: now - 60 * 60_000),
            BellService.Event(id: "e3", kind: "thanks", actor: "mom", actorName: "Мама", item: UUID().uuidString, title: "Полить цветы", at: now - 26 * 3_600_000),
        ]
        let bell = BellScreen(bell: BellService(events: events, seen: [events[2].mark]), onEvent: { _ in }, onNews: { _ in }, onBack: {})
        try render(bell, name: "P-Bell", style: .light)
        try render(bell, name: "P-Bell-Dark", style: .dark)
    }
}
