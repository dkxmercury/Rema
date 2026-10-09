import Foundation

public struct StoreSnapshot: Codable, Sendable {
    public var reminders: [Reminder]
    public var places: [Place]
    public var settings: Settings
    public var sounds: [CustomSound]?
    public var unreadable = Unreadable()

    // Entries a newer build wrote that this one cannot read; they are written back untouched instead of being lost.
    public struct Unreadable: Sendable, Equatable {
        var reminders: [JSONValue] = []
        var places: [JSONValue] = []
        var sounds: [JSONValue] = []
        var settings: JSONValue?

        public init() {}

        public var isEmpty: Bool {
            reminders.isEmpty && places.isEmpty && sounds.isEmpty && settings == nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case reminders, places, settings, sounds
    }

    public init(reminders: [Reminder], places: [Place], settings: Settings, sounds: [CustomSound]?, unreadable: Unreadable = Unreadable()) {
        self.reminders = reminders
        self.places = places
        self.settings = settings
        self.sounds = sounds
        self.unreadable = unreadable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        (reminders, unreadable.reminders) = try Self.lossy(Reminder.self, container, .reminders)
        (places, unreadable.places) = try Self.lossy(Place.self, container, .places)
        if container.contains(.sounds), (try? container.decodeNil(forKey: .sounds)) == false {
            let (read, rest) = try Self.lossy(CustomSound.self, container, .sounds)
            sounds = read
            unreadable.sounds = rest
        } else {
            sounds = nil
        }
        if let read = try? container.decode(Settings.self, forKey: .settings) {
            settings = read
        } else {
            settings = .standard(at: Date())
            unreadable.settings = try container.decode(JSONValue.self, forKey: .settings)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try Self.write(reminders, unreadable.reminders, into: &container, .reminders)
        try Self.write(places, unreadable.places, into: &container, .places)
        if let sounds {
            try Self.write(sounds, unreadable.sounds, into: &container, .sounds)
        }
        if let raw = unreadable.settings, settings.isUntouched {
            try container.encode(raw, forKey: .settings)
        } else {
            try container.encode(settings, forKey: .settings)
        }
    }

    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    private static func lossy<Value: Decodable>(_ type: Value.Type, _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> ([Value], [JSONValue]) {
        let entries = try container.decode([Lossy<Value>].self, forKey: key)
        let read = entries.compactMap(\.value)
        guard read.count < entries.count else { return (read, []) }
        let raw = try container.decode([JSONValue].self, forKey: key)
        return (read, zip(entries, raw).filter { $0.0.value == nil }.map(\.1))
    }

    private static func write<Value: Encodable>(_ values: [Value], _ raw: [JSONValue], into container: inout KeyedEncodingContainer<CodingKeys>, _ key: CodingKeys) throws {
        var list = container.nestedUnkeyedContainer(forKey: key)
        for value in values {
            try list.encode(value)
        }
        for entry in raw {
            try list.encode(entry)
        }
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

    // Only the app puts a file nothing can read aside; an extension leaves it where it is and saves nothing over it.
    public static func load(from directory: URL = directory, aside: Bool = false) -> StoreSnapshot? {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let snapshot = try? JSONDecoder().decode(StoreSnapshot.self, from: data) {
            return snapshot
        }
        if aside {
            // A file nothing can read is put aside rather than overwritten by the next save, so it can still be recovered.
            let kept = directory.appendingPathComponent("store-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: kept)
        }
        return nil
    }

    // Whether the store file exists at all; an extension must not create a new one over a file it could not read.
    public static func exists(in directory: URL = directory) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path)
    }

    // The copies put aside hold everything the account had; they go with the account.
    public static func removeAside(in directory: URL = directory) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix("store-unreadable-") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
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
            reminder.markDone(through: occurrence, at: now)
            reminder.fit()
        } else {
            reminder.reopen(before: occurrence)
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
