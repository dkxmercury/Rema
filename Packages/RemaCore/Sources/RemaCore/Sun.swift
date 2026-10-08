import Foundation

public struct Coordinate: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum SunEvent: Sendable {
    case sunrise
    case sunset
}

// Sunrise and sunset from the date and the place alone, the NOAA approximation, good to a couple of minutes and with no network.
public enum Sun {
    public static func time(_ event: SunEvent, on day: LocalDate, at place: Coordinate, calendar: Calendar) -> LocalTime? {
        guard let noon = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) else { return nil }
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: noon) ?? 1)
        let gamma = 2 * Double.pi / 365 * (dayOfYear - 1)
        let equation = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma) - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let declination = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma) - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let latitude = place.latitude * Double.pi / 180
        let cosine = cos(90.833 * Double.pi / 180) / (cos(latitude) * cos(declination)) - tan(latitude) * tan(declination)
        // Polar day or night, the sun neither rises nor sets that day.
        guard (-1...1).contains(cosine) else { return nil }
        let angle = acos(cosine) * 180 / Double.pi
        let utc = event == .sunrise ? 720 - 4 * (place.longitude + angle) - equation : 720 - 4 * (place.longitude - angle) - equation
        let local = Int((utc + Double(calendar.timeZone.secondsFromGMT(for: noon)) / 60).rounded())
        let minutes = ((local % 1_440) + 1_440) % 1_440
        return LocalTime(hour: minutes / 60, minute: minutes % 60)
    }

    private static let zones: [String: Coordinate] = [
        "Asia/Tashkent": Coordinate(latitude: 41.31, longitude: 69.24), "Asia/Samarkand": Coordinate(latitude: 39.65, longitude: 66.96),
        "Asia/Almaty": Coordinate(latitude: 43.24, longitude: 76.89), "Asia/Bishkek": Coordinate(latitude: 42.87, longitude: 74.59),
        "Asia/Dushanbe": Coordinate(latitude: 38.56, longitude: 68.79), "Asia/Ashgabat": Coordinate(latitude: 37.95, longitude: 58.38),
        "Asia/Baku": Coordinate(latitude: 40.41, longitude: 49.87), "Asia/Tbilisi": Coordinate(latitude: 41.72, longitude: 44.79),
        "Europe/Moscow": Coordinate(latitude: 55.75, longitude: 37.62), "Europe/Minsk": Coordinate(latitude: 53.90, longitude: 27.56),
        "Europe/Kiev": Coordinate(latitude: 50.45, longitude: 30.52), "Europe/Kyiv": Coordinate(latitude: 50.45, longitude: 30.52),
        "Europe/Warsaw": Coordinate(latitude: 52.23, longitude: 21.01), "Europe/Berlin": Coordinate(latitude: 52.52, longitude: 13.40),
        "Europe/Vienna": Coordinate(latitude: 48.21, longitude: 16.37), "Europe/Zurich": Coordinate(latitude: 47.38, longitude: 8.54),
        "Europe/Paris": Coordinate(latitude: 48.86, longitude: 2.35), "Europe/Brussels": Coordinate(latitude: 50.85, longitude: 4.35),
        "Europe/London": Coordinate(latitude: 51.51, longitude: -0.13), "Europe/Istanbul": Coordinate(latitude: 41.01, longitude: 28.98),
        "Asia/Dubai": Coordinate(latitude: 25.20, longitude: 55.27), "Asia/Riyadh": Coordinate(latitude: 24.71, longitude: 46.68),
        "Africa/Cairo": Coordinate(latitude: 30.04, longitude: 31.24), "America/New_York": Coordinate(latitude: 40.71, longitude: -74.01),
    ]

    // Without a known place the capital of the time zone stands in; an unknown zone gives the longitude from its offset.
    public static func guess(for calendar: Calendar) -> Coordinate {
        zones[calendar.timeZone.identifier] ?? Coordinate(latitude: 41.3, longitude: Double(calendar.timeZone.secondsFromGMT()) / 240)
    }
}
