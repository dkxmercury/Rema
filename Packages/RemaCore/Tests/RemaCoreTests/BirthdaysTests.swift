import Foundation
import Testing
@testable import RemaCore

struct BirthdaysTests {
    let created = Date(timeIntervalSince1970: 1_790_000_000)
    let today = LocalDate(year: 2026, month: 11, day: 5)
    let patterns = ["День рождения: %@", "Birthday of %@", "%@ tug\u{2018}ilgan kuni"]

    func yearly(_ title: String, _ month: Int, _ day: Int, note: BirthdayNote? = nil) -> Reminder {
        Reminder(title: title, schedule: Schedule(start: LocalDate(year: 2026, month: month, day: day), time: LocalTime(hour: 10, minute: 0), rule: .yearly(month: month, day: day)), createdAt: created, birthday: note)
    }

    @Test func birthdaysComeInTheOrderTheyAreDue() {
        let anna = yearly("День рождения: Анна Смирнова", 11, 12, note: BirthdayNote(name: "Анна Смирнова", year: 1996))
        let mom = yearly("День рождения: Мама", 1, 3)
        let ilya = yearly("Birthday of Ilya", 11, 20)
        let aziz = yearly("Aziz tug\u{2018}ilgan kuni", 11, 5)
        let server = yearly("Оплатить сервер", 10, 6)
        var gone = yearly("День рождения: Олег", 12, 1)
        gone.deletedAt = created
        let entries = Birthdays.entries([anna, mom, ilya, aziz, server, gone], today: today, patterns: patterns)
        #expect(entries.map(\.name) == ["Aziz", "Анна Смирнова", "Ilya", "Мама"])
        #expect(entries.map(\.daysLeft) == [0, 7, 15, 59])
        #expect(entries[1].turning == 30)
        #expect(entries[3].next == LocalDate(year: 2027, month: 1, day: 3))
        #expect(entries[3].turning == nil)
    }

    @Test func leapDayComesOnTheTwentyEighth() {
        #expect(Birthdays.coming(month: 2, day: 29, from: today) == LocalDate(year: 2027, month: 2, day: 28))
        #expect(Birthdays.coming(month: 2, day: 29, from: LocalDate(year: 2027, month: 3, day: 1)) == LocalDate(year: 2028, month: 2, day: 29))
    }
}
