import Foundation

public struct StoreSnapshot: Codable, Sendable {
    public var reminders: [Reminder]
    public var places: [Place]
    public var settings: Settings
    public var sounds: [CustomSound]?

    public init(reminders: [Reminder], places: [Place], settings: Settings, sounds: [CustomSound]?) {
        self.reminders = reminders
        self.places = places
        self.settings = settings
        self.sounds = sounds
    }
}

public enum SharedStore {
    public static let appGroup = "group.uz.dkx.rema"
    public static let fileName = "store.json"

    public static var groupDirectory: URL? {
        // The parser tests also run on Linux, which has no app groups.
        #if canImport(Darwin)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Rema", isDirectory: true)
        #else
        nil
        #endif
    }

    public static var localDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rema", isDirectory: true)
    }

    public static var directory: URL {
        groupDirectory ?? localDirectory
    }

    public static func load(from directory: URL = directory) -> StoreSnapshot? {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StoreSnapshot.self, from: data)
    }

    public static func save(_ snapshot: StoreSnapshot, to directory: URL = directory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    public static func modified(in directory: URL = directory) -> Date? {
        let url = directory.appendingPathComponent(fileName)
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    public static func moveLocalFileToGroup() {
        guard let group = groupDirectory else { return }
        let manager = FileManager.default
        let source = localDirectory.appendingPathComponent(fileName)
        let target = group.appendingPathComponent(fileName)
        guard manager.fileExists(atPath: source.path), !manager.fileExists(atPath: target.path) else { return }
        try? manager.createDirectory(at: group, withIntermediateDirectories: true)
        try? manager.moveItem(at: source, to: target)
    }

    public static func setDone(_ done: Bool, reminder id: UUID, occurrence: Date, in directory: URL = directory, now: Date = Date()) -> Bool {
        guard var snapshot = load(from: directory),
              let index = snapshot.reminders.firstIndex(where: { $0.id == id }) else { return false }
        var reminder = snapshot.reminders[index]
        if done {
            reminder.completedThrough = max(reminder.completedThrough ?? occurrence, occurrence)
            reminder.snoozedUntil = nil
        } else {
            reminder.completedThrough = occurrence.addingTimeInterval(-1)
        }
        reminder.updatedAt = now
        snapshot.reminders[index] = reminder
        return (try? save(snapshot, to: directory)) != nil
    }

    public static func snooze(reminder id: UUID, until date: Date, in directory: URL = directory, now: Date = Date()) -> Bool {
        guard var snapshot = load(from: directory),
              let index = snapshot.reminders.firstIndex(where: { $0.id == id }) else { return false }
        snapshot.reminders[index].snoozedUntil = date
        snapshot.reminders[index].updatedAt = now
        return (try? save(snapshot, to: directory)) != nil
    }
}
