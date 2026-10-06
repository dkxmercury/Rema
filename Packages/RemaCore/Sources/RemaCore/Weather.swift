import Foundation

public struct DayForecast: Codable, Equatable, Sendable {
    public enum Sky: String, Codable, Sendable {
        case clear
        case cloudy
        case rain
        case snow
        case storm
    }

    public let day: LocalDate
    public let sky: Sky
    public let precipitationChance: Double
    public let high: Double
    public let low: Double
    public let wind: Double

    public init(day: LocalDate, sky: Sky, precipitationChance: Double, high: Double, low: Double, wind: Double) {
        self.day = day
        self.sky = sky
        self.precipitationChance = precipitationChance
        self.high = high
        self.low = low
        self.wind = wind
    }
}

public enum WeatherEvent: Equatable, Sendable {
    case storm
    case firstSnow
    case snow
    case rain
    case wind(Double)
    case frost(Double)
    case heat(Double)
    case colder(Double)
    case sunAfterRain
    case warmWeekend(Double)
}

public struct WeatherThresholds: Equatable, Sendable {
    public var rainChance: Double
    public var wind: Double
    public var cold: Double
    public var heat: Double
    public var drop: Double

    public init(rainChance: Double, wind: Double, cold: Double, heat: Double, drop: Double) {
        self.rainChance = rainChance
        self.wind = wind
        self.cold = cold
        self.heat = heat
        self.drop = drop
    }
}

public enum WeatherRules {
    // One reason per notification, the most important first; a quiet day gives nothing.
    public static func event(for day: LocalDate, forecast: [DayForecast], lastSnow: LocalDate?, thresholds: WeatherThresholds) -> WeatherEvent? {
        let byDay = Dictionary(forecast.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        guard let today = byDay[day] else { return nil }
        let before = byDay[day.adding(days: -1)]
        let twoBefore = byDay[day.adding(days: -2)]

        func wet(_ forecast: DayForecast?) -> Bool {
            guard let forecast else { return false }
            return [.rain, .storm, .snow].contains(forecast.sky) && forecast.precipitationChance >= thresholds.rainChance
        }

        if today.sky == .storm, today.precipitationChance >= thresholds.rainChance {
            return .storm
        }
        if today.sky == .snow, today.precipitationChance >= thresholds.rainChance {
            let recent = lastSnow.map { $0 >= day.adding(days: -120) } ?? false
            return recent ? .snow : .firstSnow
        }
        if today.low <= thresholds.cold {
            return .frost(today.low)
        }
        if today.high >= thresholds.heat {
            return .heat(today.high)
        }
        if today.wind >= thresholds.wind {
            return .wind(today.wind)
        }
        if today.sky == .rain, today.precipitationChance >= thresholds.rainChance, !wet(before) {
            return .rain
        }
        if let before, before.high - today.high >= thresholds.drop {
            return .colder(before.high - today.high)
        }
        if today.sky == .clear, wet(before), wet(twoBefore) {
            return .sunAfterRain
        }
        if day.weekday == .saturday, let sunday = byDay[day.adding(days: 1)], !wet(today), !wet(sunday), min(today.high, sunday.high) >= 20 {
            return .warmWeekend(max(today.high, sunday.high))
        }
        return nil
    }
}
