import Foundation

// Values that come from outside, from the server or a friend, are checked before any date arithmetic runs on them.
// Swift traps on an overflow, and a reminder that trapped on every launch could not even be deleted.
public extension LocalDate {
    static let years = 1970...2200

    var isValid: Bool {
        Self.years.contains(year) && (1...12).contains(month) && (1...31).contains(day)
    }
}

public extension LocalTime {
    var isValid: Bool {
        (0...23).contains(hour) && (0...59).contains(minute)
    }
}

public extension RepeatRule {
    var isValid: Bool {
        switch self {
        case .daily, .weekdays, .lastWorkday, .evenDays, .oddDays:
            true
        case .weekly(let days):
            days.count <= 7
        case .everyDays(let days):
            (1...3650).contains(days)
        case .monthlyOnDay(let day):
            (1...31).contains(day)
        case .monthlyOnWeekday(let ordinal, _):
            (-5...5).contains(ordinal)
        case .yearly(let month, let day):
            (1...12).contains(month) && (1...31).contains(day)
        case .everyMonths(let months):
            (1...120).contains(months)
        }
    }
}

public extension RepeatEnd {
    var isValid: Bool {
        switch self {
        case .never:
            true
        case .until(let date):
            date.isValid
        case .count(let count):
            (0...10_000).contains(count)
        }
    }
}

public extension Schedule {
    var isValid: Bool {
        start.isValid && time.isValid && (rule?.isValid ?? true) && end.isValid && (timeZone?.count ?? 0) <= 64
    }
}

public extension Date {
    // Milliseconds since 1970 that always fit in Int64; the conversion of a Double past the range would trap.
    var milliseconds: Int64 {
        let value = (timeIntervalSince1970 * 1000).rounded()
        guard value.isFinite else { return 0 }
        return Int64(min(max(value, -9.0e18), 9.0e18))
    }

    // Milliseconds from outside turn into a date only within the years the app works with; anything else means «no date».
    static func fromMilliseconds(_ value: Int64) -> Date? {
        guard value > 0, value <= Self.farthestMilliseconds else { return nil }
        return Date(timeIntervalSince1970: Double(value) / 1000)
    }

    // The first moment of 2200.
    static let farthestMilliseconds: Int64 = 7_258_118_400_000
}

public extension Int64 {
    // A moment in milliseconds from outside, or zero when it is out of range.
    var asMilliseconds: Int64 {
        self > 0 && self <= Date.farthestMilliseconds ? self : 0
    }
}

public extension String {
    // A name other people will see: one line, no control or formatting marks that could reorder the text, a sane length.
    // The joiner stays, emoji made of several symbols need it.
    func cleanedName(limit: Int = 40) -> String {
        let kept = unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            if scalar == "\u{200D}" { return scalar }
            if scalar.properties.isWhitespace { return " " }
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned, .surrogate:
                return nil
            default:
                return scalar
            }
        }
        let joined = String(String.UnicodeScalarView(kept)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(joined.prefix(limit))
    }
}
