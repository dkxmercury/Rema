import Foundation
import Testing
@testable import RemaCore

struct ChecklistTests {
    let created = Date(timeIntervalSince1970: 1_790_000_000)

    func list(_ title: String, _ items: [String], at offset: TimeInterval = 0) -> Reminder {
        Reminder(title: title, schedule: nil, items: items.map { ChecklistItem(text: $0) }, createdAt: created, updatedAt: created.addingTimeInterval(offset))
    }

    @Test func amountStandsApart() {
        #expect(Checklist.split("Молоко 2 л") == ("Молоко", "2 л"))
        #expect(Checklist.split("Яйца 10 шт") == ("Яйца", "10 шт"))
        #expect(Checklist.split("Apples 1.5 kg") == ("Apples", "1.5 kg"))
        #expect(Checklist.split("Хлеб x2") == ("Хлеб", "x2"))
        #expect(Checklist.split("Сыр") == ("Сыр", nil))
        #expect(Checklist.split("10") == ("10", nil))
    }

    @Test func shoppingIsRecognized() {
        for title in ["Купить продукты", "закупиться в магазине", "Купити хліб", "Buy groceries", "Einkaufen gehen", "Faire les courses", "Non sotib olish", "Бозорга бориш", "شراء الخبز"] {
            #expect(Checklist.isShopping(title), "\(title)")
        }
        for title in ["Позвонить маме", "Call the bank", "Online courses", "Zahnarzt"] {
            #expect(!Checklist.isShopping(title), "\(title)")
        }
    }

    @Test func itemsComeOutOfTheTitle() {
        #expect(Checklist.items(in: "Купить хлеб, молоко и яйца") == ["Хлеб", "Молоко", "Яйца"])
        #expect(Checklist.items(in: "buy milk, bread and eggs") == ["Milk", "Bread", "Eggs"])
        #expect(Checklist.items(in: "non, sut va tuxum sotib olish") == ["Non", "Sut", "Tuxum"])
        #expect(Checklist.items(in: "اشتري خبز، حليب، بيض") == ["خبز", "حليب", "بيض"])
        #expect(Checklist.items(in: "Купить хлеб").isEmpty)
        #expect(Checklist.items(in: "Позвонить маме и папе").isEmpty)
    }

    @Test func suggestionsFollowWhatGoesTogether() {
        let reminders = [
            list("Купить продукты", ["Хлеб", "Молоко 2 л", "Яйца"], at: 10),
            list("Купить продукты", ["Хлеб", "Масло", "Яйца"], at: 20),
            list("Собрать вещи", ["Паспорт", "Зарядка"], at: 30),
        ]
        let draft = UUID()
        #expect(Checklist.suggestions(for: [ChecklistItem(text: "Хлеб")], in: reminders, excluding: draft) == ["Яйца", "Масло", "Молоко"])
        #expect(Checklist.suggestions(for: [], in: reminders, excluding: draft, limit: 2) == ["Хлеб", "Яйца"])
        #expect(Checklist.suggestions(for: [ChecklistItem(text: "Кофе")], in: reminders, excluding: draft).isEmpty)
    }

    @Test func lastTimeTakesTheNewestSimilarList() {
        let older = list("Купить продукты", ["Хлеб"], at: 10)
        let newer = list("Закупиться в магазине", ["Сыр", "Кофе"], at: 20)
        let other = list("Собрать вещи", ["Паспорт"], at: 30)
        let previous = Checklist.previous(for: "Купить продукты", in: [older, newer, other], excluding: UUID())
        #expect(previous?.map(\.text) == ["Сыр", "Кофе"])
        #expect(previous?.allSatisfy { !$0.done } == true)
        #expect(Checklist.previous(for: "Позвонить маме", in: [older, newer, other], excluding: UUID()) == nil)
    }

    @Test func oldDataHasNoItems() throws {
        let reminder = Reminder(title: "Позвонить", schedule: nil, createdAt: created)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reminder)) as! [String: Any]
        json.removeValue(forKey: "items")
        json.removeValue(forKey: "doneWhenChecked")
        let decoded = try JSONDecoder().decode(Reminder.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.items.isEmpty)
        #expect(decoded.doneWhenChecked)
        #expect(decoded.title == "Позвонить")
    }

    @Test func repeatingListComesBackUnticked() {
        let at = created.addingTimeInterval(3600)
        var weekly = Reminder(title: "Купить продукты", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 19, minute: 0), rule: .weekly([.monday])), items: [ChecklistItem(text: "Хлеб", done: true), ChecklistItem(text: "Сыр")], createdAt: created)
        weekly.markDone(through: at)
        #expect(weekly.completedThrough == at)
        #expect(weekly.items.map(\.done) == [false, false])
        var once = Reminder(title: "Купить продукты", schedule: Schedule(start: LocalDate(year: 2026, month: 10, day: 5), time: LocalTime(hour: 19, minute: 0)), items: [ChecklistItem(text: "Хлеб", done: true)], createdAt: created)
        once.markDone(through: at)
        #expect(once.items.map(\.done) == [true])
    }
}
