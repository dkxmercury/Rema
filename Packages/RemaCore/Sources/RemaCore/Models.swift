import Foundation

public struct LocalTime: Codable, Hashable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }
}

public struct LocalDate: Codable, Hashable, Comparable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public enum Weekday: Int, Codable, CaseIterable, Comparable, Sendable {
    case monday = 1
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum RepeatRule: Codable, Hashable, Sendable {
    case daily
    case weekdays
    case weekly([Weekday])
    case everyDays(Int)
    case monthlyOnDay(Int)
    case monthlyOnWeekday(ordinal: Int, weekday: Weekday)
    case yearly(month: Int, day: Int)
    case lastWorkday
    case everyMonths(Int)
    case evenDays
    case oddDays
}

public enum RepeatEnd: Codable, Hashable, Sendable {
    case never
    case until(LocalDate)
    case count(Int)
}

public struct Schedule: Codable, Hashable, Sendable {
    public var start: LocalDate
    public var time: LocalTime
    public var rule: RepeatRule?
    public var end: RepeatEnd
    // Set on a shared reminder: one moment for everybody, counted in the zone of the one who made it.
    public var timeZone: String?

    public init(start: LocalDate, time: LocalTime, rule: RepeatRule? = nil, end: RepeatEnd = .never, timeZone: String? = nil) {
        self.start = start
        self.time = time
        self.rule = rule
        self.end = end
        self.timeZone = timeZone
    }
}

public enum PlaceTrigger: String, Codable, Sendable {
    case arrive
    case leave
}

public enum SoundChoice: Codable, Hashable, Sendable {
    case standard
    case builtIn(String)
    case custom(UUID)
}

public struct ChecklistItem: Codable, Identifiable, Hashable, Sendable {
    public static let maximumLength = 120
    public static let maximumBytes = 240

    public var id: UUID
    public var text: String
    public var done: Bool

    public init(id: UUID = UUID(), text: String, done: Bool = false) {
        self.id = id
        self.text = Self.clipped(text)
        self.done = done
    }

    // Emoji built from several symbols weigh up to 35 bytes each, so characters alone do not bound the size.
    static func clipped(_ text: String) -> String {
        var clipped = String(text.prefix(maximumLength))
        while clipped.utf8.count > maximumBytes {
            clipped.removeLast()
        }
        return clipped
    }
}

// The person a reminder is about, for the «Call» button of its notification.
public struct ContactLink: Codable, Hashable, Sendable {
    public var name: String
    public var phone: String

    public init(name: String, phone: String) {
        self.name = name
        self.phone = phone
    }
}

// One tick: which occurrence and when it was given, kept short because it travels inside every reminder.
public struct DoneMark: Codable, Hashable, Sendable {
    public var occurrence: Date
    public var at: Date

    public init(occurrence: Date, at: Date) {
        self.occurrence = occurrence
        self.at = at
    }

    enum CodingKeys: String, CodingKey {
        case occurrence = "o"
        case at = "a"
    }
}

public struct Reminder: Codable, Identifiable, Hashable, Sendable {
    public static let maximumTitleLength = 200
    public static let maximumItems = 40
    public static let historyLimit = 100
    public static let maximumBytes = 15_000

    public var id: UUID
    public var title: String
    public var schedule: Schedule?
    public var preAlerts: [Int]
    public var nag: Bool
    public var nagInterval: Int?
    public var urgent: Bool
    public var placeIDs: [UUID]
    public var placeTrigger: PlaceTrigger
    public var sound: SoundChoice
    public var items: [ChecklistItem]
    public var doneWhenChecked: Bool
    public var history: [DoneMark]
    public var contact: ContactLink?
    public var shared: SharedInfo?
    public var completedThrough: Date?
    public var snoozedUntil: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        schedule: Schedule?,
        preAlerts: [Int] = [],
        nag: Bool = false,
        nagInterval: Int? = nil,
        urgent: Bool = false,
        placeIDs: [UUID] = [],
        placeTrigger: PlaceTrigger = .arrive,
        sound: SoundChoice = .standard,
        items: [ChecklistItem] = [],
        doneWhenChecked: Bool = true,
        history: [DoneMark] = [],
        contact: ContactLink? = nil,
        shared: SharedInfo? = nil,
        completedThrough: Date? = nil,
        snoozedUntil: Date? = nil,
        createdAt: Date,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.schedule = schedule
        self.preAlerts = preAlerts
        self.nag = nag
        self.nagInterval = nagInterval
        self.urgent = urgent
        self.placeIDs = placeIDs
        self.placeTrigger = placeTrigger
        self.sound = sound
        self.items = items
        self.doneWhenChecked = doneWhenChecked
        self.history = history
        self.contact = contact
        self.shared = shared
        self.completedThrough = completedThrough
        self.snoozedUntil = snoozedUntil
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }

    // Reminders saved before lists came in have no items in their data.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        schedule = try container.decodeIfPresent(Schedule.self, forKey: .schedule)
        preAlerts = try container.decode([Int].self, forKey: .preAlerts)
        nag = try container.decode(Bool.self, forKey: .nag)
        nagInterval = try container.decodeIfPresent(Int.self, forKey: .nagInterval)
        urgent = try container.decode(Bool.self, forKey: .urgent)
        placeIDs = try container.decode([UUID].self, forKey: .placeIDs)
        placeTrigger = try container.decode(PlaceTrigger.self, forKey: .placeTrigger)
        sound = try container.decode(SoundChoice.self, forKey: .sound)
        items = try container.decodeIfPresent([ChecklistItem].self, forKey: .items) ?? []
        doneWhenChecked = try container.decodeIfPresent(Bool.self, forKey: .doneWhenChecked) ?? true
        history = try container.decodeIfPresent([DoneMark].self, forKey: .history) ?? []
        contact = try container.decodeIfPresent(ContactLink.self, forKey: .contact)
        shared = try? container.decodeIfPresent(SharedInfo.self, forKey: .shared)
        completedThrough = try container.decodeIfPresent(Date.self, forKey: .completedThrough)
        snoozedUntil = try container.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    public var isPlaceOnly: Bool {
        schedule == nil && !placeIDs.isEmpty
    }

    public var checkedCount: Int {
        items.filter(\.done).count
    }

    public func isDone(_ occurrence: Date) -> Bool {
        completedThrough.map { $0 >= occurrence } ?? false
    }

    public mutating func markDone(through occurrence: Date, at moment: Date = Date()) {
        skip(through: occurrence)
        if !history.contains(where: { $0.occurrence == occurrence }) {
            history.append(DoneMark(occurrence: occurrence, at: moment))
            if history.count > Self.historyLimit {
                history.removeFirst(history.count - Self.historyLimit)
            }
        }
    }

    // Moves on like a tick but leaves no mark, and a repeating list comes back unticked for the next time.
    public mutating func skip(through occurrence: Date) {
        completedThrough = max(completedThrough ?? occurrence, occurrence)
        snoozedUntil = nil
        if schedule?.rule != nil {
            for index in items.indices {
                items[index].done = false
            }
        }
    }

    public mutating func reopen(before occurrence: Date) {
        completedThrough = occurrence.addingTimeInterval(-1)
        history.removeAll { $0.occurrence >= occurrence }
    }

    // The server refuses a reminder over 16 KB and it would stay on this phone for good, so the oldest ticks go first.
    public mutating func fit(within limit: Int = Reminder.maximumBytes) {
        let encoder = JSONEncoder()
        func size() -> Int { (try? encoder.encode(self).count) ?? 0 }
        guard size() > limit else { return }
        while !history.isEmpty, size() > limit {
            history.removeFirst(min(10, history.count))
        }
        while !items.isEmpty, size() > limit {
            items.removeLast()
        }
    }
}

public struct Place: Codable, Identifiable, Hashable, Sendable {
    public static let maximumCount = 20
    public static let radiusRange: ClosedRange<Double> = 100...1000

    public var id: UUID
    public var name: String
    public var icon: String
    public var latitude: Double
    public var longitude: Double
    public var radius: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var remembered: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        latitude: Double,
        longitude: Double,
        radius: Double,
        createdAt: Date,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        remembered: Bool = true
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.latitude = latitude
        self.longitude = longitude
        self.radius = min(max(radius, Self.radiusRange.lowerBound), Self.radiusRange.upperBound)
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
        self.remembered = remembered
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        radius = try container.decode(Double.self, forKey: .radius)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        remembered = try container.decodeIfPresent(Bool.self, forKey: .remembered) ?? true
    }
}

public enum Appearance: String, Codable, Sendable {
    case system
    case light
    case dark
}

public struct Settings: Codable, Hashable, Sendable {
    public var defaultSound: SoundChoice
    public var morning: LocalTime
    public var evening: LocalTime
    public var nagInterval: Int
    public var appearance: Appearance
    public var updatedAt: Date
    // Set by the first change, so settings put back to the defaults still reach the other phones.
    public var touched: Bool?
    public var snoozeOptions: [Int]?

    public init(defaultSound: SoundChoice, morning: LocalTime, evening: LocalTime, nagInterval: Int, appearance: Appearance, updatedAt: Date, touched: Bool? = nil, snoozeOptions: [Int]? = nil) {
        self.defaultSound = defaultSound
        self.morning = morning
        self.evening = evening
        self.nagInterval = nagInterval
        self.appearance = appearance
        self.updatedAt = updatedAt
        self.touched = touched
        self.snoozeOptions = snoozeOptions
    }

    public static func standard(at date: Date) -> Settings {
        Settings(
            defaultSound: .builtIn("mechanika"),
            morning: LocalTime(hour: 9, minute: 0),
            evening: LocalTime(hour: 19, minute: 0),
            nagInterval: 5,
            appearance: .system,
            updatedAt: date
        )
    }
}

// Minutes to put a reminder off by; the two negative values are moments of the day.
public enum SnoozeOption {
    public static let tomorrowMorning = -1
    public static let thisEvening = -2
    public static let standard = [10, 60, -1]
    public static let all = [5, 10, 15, 30, 60, 120, 180, -2, -1]
    public static let limit = 3
}

public enum BuiltInSound: String, CaseIterable, Codable, Sendable {
    case mechanika
    case bell
    case drops
    case ticktock
    case soft
    case silent

    public var fileName: String? {
        self == .silent ? nil : "sound-\(rawValue).caf"
    }
}

public struct CustomSound: Codable, Identifiable, Hashable, Sendable {
    public static let maximumSeconds = 30.0

    public var id: UUID
    public var name: String
    public var duration: Double
    public var createdAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), name: String, duration: Double, createdAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.duration = min(duration, Self.maximumSeconds)
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }

    public var fileName: String {
        "custom-\(id.uuidString).caf"
    }
}
