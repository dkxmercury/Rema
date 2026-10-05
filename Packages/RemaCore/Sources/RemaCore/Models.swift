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

    public init(start: LocalDate, time: LocalTime, rule: RepeatRule? = nil, end: RepeatEnd = .never) {
        self.start = start
        self.time = time
        self.rule = rule
        self.end = end
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

public struct Reminder: Codable, Identifiable, Hashable, Sendable {
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
        self.completedThrough = completedThrough
        self.snoozedUntil = snoozedUntil
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }

    public var isPlaceOnly: Bool {
        schedule == nil && !placeIDs.isEmpty
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

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        latitude: Double,
        longitude: Double,
        radius: Double,
        createdAt: Date,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
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

    public init(defaultSound: SoundChoice, morning: LocalTime, evening: LocalTime, nagInterval: Int, appearance: Appearance, updatedAt: Date) {
        self.defaultSound = defaultSound
        self.morning = morning
        self.evening = evening
        self.nagInterval = nagInterval
        self.appearance = appearance
        self.updatedAt = updatedAt
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
