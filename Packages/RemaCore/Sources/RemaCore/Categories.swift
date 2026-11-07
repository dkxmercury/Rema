import Foundation

// A person's own group of reminders, like «Work» or «Home»; which group a reminder is in lives in the reminder itself.
public struct ReminderCategory: Codable, Hashable, Identifiable, Sendable {
    public static let limit = 20
    public static let nameLimit = 30
    public static let colorCount = 8

    public var id: UUID
    public var name: String
    public var color: Int

    public init(id: UUID = UUID(), name: String, color: Int) {
        self.id = id
        self.name = String(name.prefix(Self.nameLimit))
        self.color = Self.wrap(color)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = String(try container.decode(String.self, forKey: .name).prefix(Self.nameLimit))
        color = Self.wrap((try? container.decode(Int.self, forKey: .color)) ?? 0)
    }

    private static func wrap(_ color: Int) -> Int {
        (color % colorCount + colorCount) % colorCount
    }
}

// Whose birthday a yearly reminder is, and the year when it is known, for the age.
public struct BirthdayNote: Codable, Hashable, Sendable {
    public static let nameLimit = 80

    public var name: String
    public var year: Int?

    public init(name: String, year: Int? = nil) {
        self.name = String(name.prefix(Self.nameLimit))
        self.year = year.flatMap { (1900...2100).contains($0) ? $0 : nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try container.decode(String.self, forKey: .name), year: (try? container.decodeIfPresent(Int.self, forKey: .year)) ?? nil)
    }

    // The age the coming birthday brings.
    public func age(on day: LocalDate) -> Int? {
        guard let year, day.year > year else { return nil }
        return day.year - year
    }
}

extension Settings {
    public func category(_ id: UUID?) -> ReminderCategory? {
        guard let id else { return nil }
        return categories?.first { $0.id == id }
    }

    // A new one takes the colour used least, so neighbours rarely look alike.
    @discardableResult
    public mutating func addCategory(named name: String) -> ReminderCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = categories ?? []
        guard !trimmed.isEmpty, list.count < ReminderCategory.limit else { return nil }
        let used = list.map(\.color)
        let color = (0..<ReminderCategory.colorCount).min { first, second in
            let a = used.filter { $0 == first }.count
            let b = used.filter { $0 == second }.count
            return a == b ? first < second : a < b
        } ?? 0
        let category = ReminderCategory(name: trimmed, color: color)
        list.append(category)
        categories = list
        return category
    }

    public mutating func renameCategory(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = categories?.firstIndex(where: { $0.id == id }) else { return }
        categories?[index].name = String(trimmed.prefix(ReminderCategory.nameLimit))
    }

    // Its reminders stay and simply have no category any more.
    public mutating func removeCategory(_ id: UUID) {
        categories = (categories ?? []).filter { $0.id != id }
    }

    public mutating func moveCategories(from source: IndexSet, to destination: Int) {
        var list = categories ?? []
        let picked = source.filter { list.indices.contains($0) }.sorted()
        guard !picked.isEmpty else { return }
        let moving = picked.map { list[$0] }
        let target = min(max(destination, 0), list.count) - picked.filter { $0 < destination }.count
        for index in picked.reversed() {
            list.remove(at: index)
        }
        list.insert(contentsOf: moving, at: min(max(target, 0), list.count))
        categories = list
    }
}
