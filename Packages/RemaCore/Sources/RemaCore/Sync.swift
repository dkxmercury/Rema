import Foundation

public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public init<Value: Encodable>(encoding value: Value) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    public func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
}

public enum SyncKind: String, Codable, CaseIterable, Sendable {
    case reminders
    case places
    case sounds
    case prefs
}

public struct SyncChange: Codable, Equatable, Sendable {
    public var kind: SyncKind
    public var clientId: String
    public var data: JSONValue?
    public var clientUpdatedAt: Int64
    public var deleted: Bool

    public init(kind: SyncKind, clientId: String, data: JSONValue?, clientUpdatedAt: Int64, deleted: Bool) {
        self.kind = kind
        self.clientId = clientId
        self.data = data
        self.clientUpdatedAt = clientUpdatedAt
        self.deleted = deleted
    }

    var key: String {
        SyncState.key(kind, clientId)
    }
}

public struct SyncRecord: Codable, Equatable, Sendable {
    public var kind: String
    public var clientId: String
    public var data: JSONValue?
    public var clientUpdatedAt: Int64
    public var deleted: Bool
    public var file: String?
    public var seq: Int64

    public init(kind: String, clientId: String, data: JSONValue?, clientUpdatedAt: Int64, deleted: Bool, file: String? = nil, seq: Int64) {
        self.kind = kind
        self.clientId = clientId
        self.data = data
        self.clientUpdatedAt = clientUpdatedAt
        self.deleted = deleted
        self.file = file
        self.seq = seq
    }
}

public struct SyncRejection: Codable, Equatable, Sendable {
    public var kind: String
    public var clientId: String
    public var reason: String

    public init(kind: String, clientId: String, reason: String) {
        self.kind = kind
        self.clientId = clientId
        self.reason = reason
    }
}

public struct SyncRequest: Codable, Equatable, Sendable {
    public var since: Int64
    public var changes: [SyncChange]

    public init(since: Int64, changes: [SyncChange]) {
        self.since = since
        self.changes = changes
    }
}

public struct SyncResponse: Codable, Equatable, Sendable {
    public var records: [SyncRecord]
    public var rejected: [SyncRejection]
    public var cursor: Int64
    public var more: Bool

    public init(records: [SyncRecord], rejected: [SyncRejection], cursor: Int64, more: Bool) {
        self.records = records
        self.rejected = rejected
        self.cursor = cursor
        self.more = more
    }
}

public struct SyncState: Codable, Equatable, Sendable {
    public var account: String?
    public var cursor: Int64
    public var lastSync: Date?
    public var known: [String: Int64]
    // Versions the server refused; they wait for the next edit and stay out of the full resync.
    public var held: [String: Int64]?
    public var appVersion: String?

    public init(account: String? = nil, cursor: Int64 = 0, lastSync: Date? = nil, known: [String: Int64] = [:], held: [String: Int64]? = nil, appVersion: String? = nil) {
        self.account = account
        self.cursor = cursor
        self.lastSync = lastSync
        self.known = known
        self.held = held
        self.appVersion = appVersion
    }

    func sent(_ key: String) -> Int64 {
        max(known[key] ?? 0, held?[key] ?? 0)
    }

    public static func key(_ kind: SyncKind, _ clientId: String) -> String {
        "\(kind.rawValue)/\(clientId)"
    }

    public static let settingsID = "settings"

    // The server forgets deletions after 180 days, so a phone that slept for 90 must read everything again.
    public func needsFullResync(now: Date) -> Bool {
        guard let lastSync else { return cursor > 0 }
        return now.timeIntervalSince(lastSync) > 90 * 86_400
    }
}

public extension Settings {
    // Fresh defaults on a new phone must not override the settings already in the account.
    var isUntouched: Bool {
        self == Settings.standard(at: updatedAt)
    }
}

public enum SyncStamp {
    public static func of(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func of(_ reminder: Reminder) -> Int64 { of(reminder.updatedAt) }
    static func of(_ place: Place) -> Int64 { of(place.updatedAt) }
    static func of(_ sound: CustomSound) -> Int64 { of(sound.deletedAt ?? sound.createdAt) }
    static func of(_ settings: Settings) -> Int64 { settings.isUntouched ? 0 : of(settings.updatedAt) }
}

public enum SyncPlan {
    public static func changes(in snapshot: StoreSnapshot, state: SyncState, limit: Int = 250) -> [SyncChange] {
        var changes: [SyncChange] = []

        func add<Item: Encodable>(_ kind: SyncKind, _ id: String, _ item: Item, stamp: Int64, deleted: Bool) {
            guard changes.count < limit, stamp > 0, stamp > state.sent(SyncState.key(kind, id)) else { return }
            let data = deleted ? nil : try? JSONValue(encoding: item)
            guard deleted || data != nil else { return }
            changes.append(SyncChange(kind: kind, clientId: id, data: data, clientUpdatedAt: stamp, deleted: deleted))
        }

        add(.prefs, SyncState.settingsID, snapshot.settings, stamp: SyncStamp.of(snapshot.settings), deleted: false)
        for place in snapshot.places {
            add(.places, place.id.uuidString, place, stamp: SyncStamp.of(place), deleted: place.deletedAt != nil)
        }
        for sound in snapshot.sounds ?? [] {
            add(.sounds, sound.id.uuidString, sound, stamp: SyncStamp.of(sound), deleted: sound.deletedAt != nil)
        }
        for reminder in snapshot.reminders {
            add(.reminders, reminder.id.uuidString, reminder, stamp: SyncStamp.of(reminder), deleted: reminder.deletedAt != nil)
        }
        return changes
    }

    // A version the server refused stays only on this phone until it is edited again.
    public static func hasRefused(in snapshot: StoreSnapshot, state: SyncState) -> Bool {
        guard let held = state.held, !held.isEmpty else { return false }
        func refused(_ kind: SyncKind, _ id: String, _ stamp: Int64) -> Bool {
            let key = SyncState.key(kind, id)
            return stamp > 0 && held[key] == stamp && stamp > (state.known[key] ?? 0)
        }
        return refused(.prefs, SyncState.settingsID, SyncStamp.of(snapshot.settings))
            || snapshot.places.contains { refused(.places, $0.id.uuidString, SyncStamp.of($0)) }
            || (snapshot.sounds ?? []).contains { refused(.sounds, $0.id.uuidString, SyncStamp.of($0)) }
            || snapshot.reminders.contains { refused(.reminders, $0.id.uuidString, SyncStamp.of($0)) }
    }
}

public enum SyncMerge {
    public struct Outcome: Sendable {
        public var snapshot: StoreSnapshot
        public var state: SyncState
        public var changed: Bool
        public var rejected: [SyncRejection]
        public var soundFiles: [UUID: String]
    }

    public static func apply(_ response: SyncResponse, sent: [SyncChange], to snapshot: StoreSnapshot, state: SyncState, now: Date) -> Outcome {
        var merger = Merger(snapshot: snapshot, state: state)
        let rejected = Set(response.rejected.map { "\($0.kind)/\($0.clientId)" })
        for change in sent {
            merger.acknowledge(change, rejected: rejected.contains(change.key))
        }
        for record in response.records {
            merger.receive(record)
        }
        merger.state.cursor = max(merger.state.cursor, response.cursor)
        merger.state.lastSync = now
        return Outcome(snapshot: merger.snapshot, state: merger.state, changed: merger.changed, rejected: response.rejected, soundFiles: merger.soundFiles)
    }

    // After reading everything from the start, local records the server once had but no longer lists were deleted long ago.
    public static func reconcile(_ snapshot: StoreSnapshot, state: SyncState, seen: Set<String>) -> Outcome {
        var merger = Merger(snapshot: snapshot, state: state)
        for key in state.known.keys where !seen.contains(key) {
            merger.forget(key)
        }
        return Outcome(snapshot: merger.snapshot, state: merger.state, changed: merger.changed, rejected: [], soundFiles: [:])
    }
}

private struct Merger {
    var snapshot: StoreSnapshot
    var state: SyncState
    var changed = false
    var soundFiles: [UUID: String] = [:]

    mutating func acknowledge(_ change: SyncChange, rejected: Bool) {
        if rejected {
            var held = state.held ?? [:]
            held[change.key] = change.clientUpdatedAt
            state.held = held
            return
        }
        state.known[change.key] = change.clientUpdatedAt
        state.held?[change.key] = nil
        guard change.deleted, let id = UUID(uuidString: change.clientId) else { return }
        switch change.kind {
        case .reminders:
            var reminders = snapshot.reminders
            purge(&reminders, id: id, stamp: change.clientUpdatedAt, key: change.key) { $0.deletedAt != nil && SyncStamp.of($0) == $1 }
            snapshot.reminders = reminders
        case .places:
            var places = snapshot.places
            purge(&places, id: id, stamp: change.clientUpdatedAt, key: change.key) { $0.deletedAt != nil && SyncStamp.of($0) == $1 }
            snapshot.places = places
        case .sounds:
            var sounds = snapshot.sounds ?? []
            purge(&sounds, id: id, stamp: change.clientUpdatedAt, key: change.key) { $0.deletedAt != nil && SyncStamp.of($0) == $1 }
            snapshot.sounds = sounds
        case .prefs:
            break
        }
    }

    private mutating func purge<Item: Identifiable>(_ items: inout [Item], id: UUID, stamp: Int64, key: String, matches: (Item, Int64) -> Bool) where Item.ID == UUID {
        guard let index = items.firstIndex(where: { $0.id == id }), matches(items[index], stamp) else { return }
        items.remove(at: index)
        state.known[key] = nil
        changed = true
    }

    mutating func receive(_ record: SyncRecord) {
        guard let kind = SyncKind(rawValue: record.kind) else { return }
        let key = SyncState.key(kind, record.clientId)
        if kind == .prefs {
            receiveSettings(record, key: key)
            return
        }
        guard let id = UUID(uuidString: record.clientId) else { return }
        switch kind {
        case .reminders:
            var reminders = snapshot.reminders
            merge(&reminders, id: id, record: record, key: key, stamp: SyncStamp.of)
            snapshot.reminders = reminders
        case .places:
            var places = snapshot.places
            merge(&places, id: id, record: record, key: key, stamp: SyncStamp.of)
            snapshot.places = places
        case .sounds:
            var sounds = snapshot.sounds ?? []
            merge(&sounds, id: id, record: record, key: key, stamp: SyncStamp.of)
            snapshot.sounds = sounds
            if !record.deleted {
                soundFiles[id] = record.file ?? ""
            }
        case .prefs:
            break
        }
    }

    private mutating func merge<Item: Codable & Identifiable & Equatable>(_ items: inout [Item], id: UUID, record: SyncRecord, key: String, stamp: (Item) -> Int64) where Item.ID == UUID {
        let index = items.firstIndex { $0.id == id }
        let local = index.map { stamp(items[$0]) }
        if let local, local > record.clientUpdatedAt {
            state.known[key] = record.clientUpdatedAt
            return
        }
        if record.deleted {
            if let index {
                items.remove(at: index)
                changed = true
            }
            state.known[key] = nil
            return
        }
        guard let data = record.data, let item = try? data.decode(Item.self), item.id == id else { return }
        state.known[key] = record.clientUpdatedAt
        if let index {
            if local != record.clientUpdatedAt || items[index] != item {
                items[index] = item
                changed = true
            }
        } else {
            items.append(item)
            changed = true
        }
    }

    private mutating func receiveSettings(_ record: SyncRecord, key: String) {
        guard record.clientId == SyncState.settingsID, !record.deleted else { return }
        let local = SyncStamp.of(snapshot.settings)
        if local > record.clientUpdatedAt {
            state.known[key] = record.clientUpdatedAt
            return
        }
        guard let data = record.data, let settings = try? data.decode(Settings.self) else { return }
        state.known[key] = record.clientUpdatedAt
        if settings != snapshot.settings {
            snapshot.settings = settings
            changed = true
        }
    }

    mutating func forget(_ key: String) {
        let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = SyncKind(rawValue: parts[0]) else { return }
        state.known[key] = nil
        guard let id = UUID(uuidString: parts[1]) else { return }
        switch kind {
        case .reminders:
            if let index = snapshot.reminders.firstIndex(where: { $0.id == id }) {
                snapshot.reminders.remove(at: index)
                changed = true
            }
        case .places:
            if let index = snapshot.places.firstIndex(where: { $0.id == id }) {
                snapshot.places.remove(at: index)
                changed = true
            }
        case .sounds:
            if let index = snapshot.sounds?.firstIndex(where: { $0.id == id }) {
                snapshot.sounds?.remove(at: index)
                changed = true
            }
        case .prefs:
            break
        }
    }
}
