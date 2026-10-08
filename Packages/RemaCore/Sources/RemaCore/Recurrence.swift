import Foundation

public enum Recurrence {
    private static let maximumSteps = 200_000

    public static func next(_ schedule: Schedule, after date: Date, limit: Int, calendar: Calendar) -> [Date] {
        var calendar = calendar
        if let zone = schedule.timeZone.flatMap(TimeZone.init(identifier:)) {
            calendar.timeZone = zone
        }
        var result: [Date] = []
        var ordinal = 0
        let floor = LocalDate(date, in: calendar).adding(days: -1)
        var days = DaySequence(schedule: schedule, from: floor)
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
            // A day before the one asked about can't be later than it, so its date is never built.
            if day < floor {
                continue
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

    // Starts next to the floor instead of walking from the first day; a count end needs every day counted, so it walks.
    init(schedule: Schedule, from floor: LocalDate? = nil) {
        self.schedule = schedule
        guard let floor, let rule = schedule.rule, floor > schedule.start else { return }
        if case .count = schedule.end {
            return
        }
        let start = schedule.start
        switch rule {
        case .daily, .weekdays, .weekly, .evenDays, .oddDays:
            cursor = floor.adding(days: -1)
        case .everyDays(let interval):
            let step = max(1, interval)
            let jumps = (floor.dayNumber - start.dayNumber + step - 1) / step
            if jumps > 0 {
                cursor = start.adding(days: (jumps - 1) * step)
            }
        case .monthlyOnDay, .monthlyOnWeekday, .lastWorkday:
            period = max(0, (floor.year - start.year) * 12 + floor.month - start.month - 1)
        case .everyMonths(let interval):
            period = max(0, ((floor.year - start.year) * 12 + floor.month - start.month) / max(1, interval) - 1)
        case .yearly:
            period = max(0, floor.year - start.year - 1)
        }
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
        case .evenDays:
            return advance(by: 1) { $0.day % 2 == 0 }
        case .oddDays:
            return advance(by: 1) { $0.day % 2 == 1 }
        case .everyMonths(let interval):
            let step = max(1, interval)
            while true {
                let monthIndex = start.month - 1 + period * step
                period += 1
                let year = start.year + monthIndex / 12
                let month = monthIndex % 12 + 1
                let candidate = LocalDate(year: year, month: month, day: min(start.day, LocalDate.days(in: month, year: year)))
                if candidate >= start {
                    return candidate
                }
            }
        case .lastWorkday:
            return nextMonth { year, month in
                var day = LocalDate(year: year, month: month, day: LocalDate.days(in: month, year: year))
                while day.weekday.rawValue > 5 {
                    day = day.adding(days: -1)
                }
                return day
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

    // Days since 1 January 1970 in the civil calendar; plain arithmetic keeps the repeat search away from Calendar.
    var dayNumber: Int {
        let shifted = month <= 2 ? year - 1 : year
        let era = (shifted >= 0 ? shifted : shifted - 399) / 400
        let yearOfEra = shifted - era * 400
        let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    init(dayNumber: Int) {
        let shifted = dayNumber + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        self.init(year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(dayNumber: dayNumber + days)
    }

    public var weekday: Weekday {
        Weekday(rawValue: ((dayNumber % 7 + 7) % 7 + 3) % 7 + 1)!
    }

    public static func days(in month: Int, year: Int) -> Int {
        switch month {
        case 2: year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
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
