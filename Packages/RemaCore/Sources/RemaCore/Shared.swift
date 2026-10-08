import Foundation

public enum DoneMode: String, Codable, Sendable {
    case each
    case one
}

public enum SharedStatus {
    public static let owner = "owner"
    public static let invited = "invited"
    public static let accepted = "accepted"
    public static let declined = "declined"
    public static let left = "left"
}

public struct SharedPerson: Codable, Hashable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case id, name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
    }
}

public struct SharedMember: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var status: String
    public var doneThrough: Int64

    public init(id: String, name: String, status: String, doneThrough: Int64 = 0) {
        self.id = id
        self.name = name
        self.status = status
        self.doneThrough = doneThrough
    }

    enum CodingKeys: String, CodingKey {
        case id, name, status, doneThrough
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? SharedStatus.invited
        doneThrough = try container.decodeIfPresent(Int64.self, forKey: .doneThrough) ?? 0
    }
}

// A reminder shared with friends: who made it, who is in it, and whether one «done» counts for everybody.
public struct SharedInfo: Codable, Hashable, Sendable {
    public var owner: SharedPerson
    public var status: String
    public var members: [SharedMember]
    public var doneMode: DoneMode
    // Made without a connection, the friends do not have it yet.
    public var pending: Bool
    // The server's number of the state this copy is in; an older one arriving late is not applied over it.
    public var seq: Int64

    public init(owner: SharedPerson, status: String, members: [SharedMember], doneMode: DoneMode, pending: Bool = false, seq: Int64 = 0) {
        self.owner = owner
        self.status = status
        self.members = members
        self.doneMode = doneMode
        self.pending = pending
        self.seq = seq
    }

    enum CodingKeys: String, CodingKey {
        case owner, status, members, doneMode, pending, seq
    }

    // Read leniently, so a reminder saved by an earlier build stays shared and is not turned into a personal one.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        owner = try container.decode(SharedPerson.self, forKey: .owner)
        status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? SharedStatus.accepted
        members = (try? container.decodeIfPresent([SharedMember].self, forKey: .members)) ?? []
        doneMode = (try? container.decodeIfPresent(DoneMode.self, forKey: .doneMode)) ?? .each
        pending = (try? container.decodeIfPresent(Bool.self, forKey: .pending)) ?? false
        seq = (try? container.decodeIfPresent(Int64.self, forKey: .seq)) ?? 0
    }

    public var isMine: Bool {
        status == SharedStatus.owner
    }

    public var isInvitation: Bool {
        status == SharedStatus.invited
    }
}

// What goes to the friends: the title and the time in the zone of the one who made it. Early alerts, persistence and the sound stay with each person.
public struct SharedData: Codable, Hashable, Sendable {
    public var title: String
    public var schedule: Schedule?
    public var doneMode: DoneMode

    public init(title: String, schedule: Schedule?, doneMode: DoneMode) {
        self.title = title
        self.schedule = schedule
        self.doneMode = doneMode
    }

    enum CodingKeys: String, CodingKey {
        case title, schedule, doneMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        schedule = try? container.decodeIfPresent(Schedule.self, forKey: .schedule)
        doneMode = (try? container.decodeIfPresent(DoneMode.self, forKey: .doneMode)) ?? .each
    }
}

// One shared reminder as the server sends it. PocketBase sends empty fields as zero or null, so everything is read leniently.
public struct SharedItem: Decodable, Sendable {
    public var id: String
    public var gone: Bool
    public var owner: SharedPerson?
    public var data: SharedData?
    public var clientUpdatedAt: Int64
    public var doneThrough: Int64
    public var myDone: Int64
    public var myStatus: String
    public var members: [SharedMember]
    public var seq: Int64
    // A push carries the reminder without the participants; the ones already known stay.
    public var partial: Bool

    enum CodingKeys: String, CodingKey {
        case id, gone, owner, data, clientUpdatedAt, doneThrough, myDone, myStatus, members, seq, partial
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        gone = (try? container.decodeIfPresent(Bool.self, forKey: .gone)) ?? false
        owner = try? container.decodeIfPresent(SharedPerson.self, forKey: .owner)
        data = try? container.decodeIfPresent(SharedData.self, forKey: .data)
        clientUpdatedAt = (try? container.decodeIfPresent(Int64.self, forKey: .clientUpdatedAt)) ?? 0
        doneThrough = (try? container.decodeIfPresent(Int64.self, forKey: .doneThrough)) ?? 0
        myDone = (try? container.decodeIfPresent(Int64.self, forKey: .myDone)) ?? 0
        myStatus = (try? container.decodeIfPresent(String.self, forKey: .myStatus)) ?? SharedStatus.invited
        members = (try? container.decodeIfPresent([SharedMember].self, forKey: .members)) ?? []
        seq = (try? container.decodeIfPresent(Int64.self, forKey: .seq)) ?? 0
        partial = (try? container.decodeIfPresent(Bool.self, forKey: .partial)) ?? false
    }
}

public extension Reminder {
    // An invitation not answered yet neither rings nor fills the day.
    var isLive: Bool {
        deletedAt == nil && shared?.isInvitation != true
    }

    var sharedData: SharedData {
        SharedData(title: title, schedule: schedule, doneMode: shared?.doneMode ?? .each)
    }
}

public enum SharedMerge {
    // Items from the server become reminders here. What each person keeps for themselves stays: early alerts, persistence, the sound,
    // a list, a snooze, the ticks of the history. Reminders with changes still waiting to be sent are left as they are.
    public static func apply(_ items: [SharedItem], to reminders: [Reminder], waiting: Set<UUID>, now: Date) -> [Reminder] {
        var result = reminders
        for item in items {
            guard let id = UUID(uuidString: item.id), !waiting.contains(id) else { continue }
            let index = result.firstIndex { $0.id == id }
            // A push may come later than the sync that already brought something newer.
            if let index, let known = result[index].shared?.seq, item.seq > 0, item.seq < known {
                continue
            }
            if item.gone || item.data == nil || item.owner == nil {
                if let index, result[index].shared != nil {
                    result.remove(at: index)
                }
                continue
            }
            guard let data = item.data, let owner = item.owner else { continue }
            var reminder = index.map { result[$0] } ?? Reminder(id: id, title: data.title, schedule: data.schedule, createdAt: now)
            reminder.title = String(data.title.prefix(Reminder.maximumTitleLength))
            reminder.schedule = data.schedule
            let members = item.partial ? reminder.shared?.members ?? [] : item.members
            reminder.shared = SharedInfo(owner: owner, status: item.myStatus, members: members, doneMode: data.doneMode, seq: item.seq)
            let through = data.doneMode == .one ? item.doneThrough : item.myDone
            let done = through > 0 ? Date(timeIntervalSince1970: Double(through) / 1000) : nil
            // The server keeps milliseconds, a tick made here may have more; under a second apart is the same tick.
            let same = done.map { day in reminder.completedThrough.map { abs($0.timeIntervalSince(day)) < 1 } ?? false } ?? (reminder.completedThrough == nil)
            if !same {
                if let done, done > (reminder.completedThrough ?? .distantPast) {
                    reminder.markDone(through: done, at: now)
                } else if let done {
                    reminder.reopen(before: done.addingTimeInterval(1))
                } else {
                    reminder.completedThrough = nil
                    reminder.history = []
                }
            }
            reminder.deletedAt = nil
            if let index {
                result[index] = reminder
            } else {
                result.append(reminder)
            }
        }
        return result
    }
}
