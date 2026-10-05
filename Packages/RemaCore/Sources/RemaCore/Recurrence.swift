import Foundation

public enum Recurrence {
    private static let maximumSteps = 200_000

    public static func next(_ schedule: Schedule, after date: Date, limit: Int, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var ordinal = 0
        var days = DaySequence(schedule: schedule)
        var steps = 0
        while result.count < limit, steps < maximumSteps, let day = days.next() {
            steps += 1
            ordinal += 1
            if case .count(let total) = schedule.end, ordinal > total {
                break
            }
            if case .until(let last) = schedule.end, day > last {
                break
            }
            let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: schedule.time.hour, minute: schedule.time.minute)
            guard let moment = calendar.date(from: components), moment > date else {
                continue
            }
            result.append(moment)
        }
        return result
    }
}

struct DaySequence {
    private let schedule: Schedule
    private var cursor: LocalDate?
    private var period = 0
    private var finished = false

    init(schedule: Schedule) {
        self.schedule = schedule
    }

    mutating func next() -> LocalDate? {
        guard !finished else { return nil }
        let start = schedule.start
        guard let rule = schedule.rule else {
            finished = true
            return start
        }
        switch rule {
        case .daily:
            return advance(by: 1) { _ in true }
        case .weekdays:
            return advance(by: 1) { $0.weekday.rawValue <= 5 }
        case .weekly(let days):
            let set: Set<Weekday> = days.isEmpty ? [start.weekday] : Set(days)
            return advance(by: 1) { set.contains($0.weekday) }
        case .everyDays(let interval):
            return advance(by: max(1, interval)) { _ in true }
        case .monthlyOnDay(let day):
            return nextMonth { year, month in
                LocalDate(year: year, month: month, day: min(max(1, day), LocalDate.days(in: month, year: year)))
            }
        case .monthlyOnWeekday(let ordinal, let weekday):
            return nextMonth { year, month in
                LocalDate.nth(ordinal, weekday, month: month, year: year)
            }
        case .yearly(let month, let day):
            while true {
                let year = start.year + period
                period += 1
                let candidate = LocalDate(year: year, month: month, day: min(day, LocalDate.days(in: month, year: year)))
                if candidate >= start {
                    return candidate
                }
            }
        }
    }

    private mutating func advance(by step: Int, where accept: (LocalDate) -> Bool) -> LocalDate? {
        var candidate = cursor.map { $0.adding(days: step) } ?? schedule.start
        while !accept(candidate) {
            candidate = candidate.adding(days: step)
        }
        cursor = candidate
        return candidate
    }

    private mutating func nextMonth(_ make: (Int, Int) -> LocalDate) -> LocalDate? {
        let start = schedule.start
        while true {
            let monthIndex = start.month - 1 + period
            period += 1
            let candidate = make(start.year + monthIndex / 12, monthIndex % 12 + 1)
            if candidate >= start {
                return candidate
            }
        }
    }
}

extension LocalDate {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    var noon: Date {
        LocalDate.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    init(_ date: Date) {
        let parts = LocalDate.utc.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    public init(_ date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(noon.addingTimeInterval(Double(days) * 86_400))
    }

    public var weekday: Weekday {
        let sundayFirst = LocalDate.utc.component(.weekday, from: noon)
        return Weekday(rawValue: (sundayFirst + 5) % 7 + 1)!
    }

    public static func days(in month: Int, year: Int) -> Int {
        let first = LocalDate(year: year, month: month, day: 1).noon
        return utc.range(of: .day, in: .month, for: first)!.count
    }

    static func nth(_ ordinal: Int, _ weekday: Weekday, month: Int, year: Int) -> LocalDate {
        let count = days(in: month, year: year)
        if ordinal < 0 {
            var day = LocalDate(year: year, month: month, day: count)
            while day.weekday != weekday {
                day = day.adding(days: -1)
            }
            return day
        }
        var day = LocalDate(year: year, month: month, day: 1)
        while day.weekday != weekday {
            day = day.adding(days: 1)
        }
        let target = day.adding(days: 7 * (max(1, ordinal) - 1))
        return target.month == month ? target : target.adding(days: -7)
    }
}
