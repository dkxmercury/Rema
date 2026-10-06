import CoreLocation
import Foundation
import Observation
import RemaCore
import WeatherKit

struct WeatherNote: Codable, Equatable {
    let fireDate: Date
    let title: String
    let body: String

    var identifier: String {
        "weather.\(Int(fireDate.timeIntervalSince1970))"
    }
}

@MainActor
@Observable
final class WeatherAdvisor {
    static let shared = WeatherAdvisor()

    private static let enabledKey = "weather.enabled"
    private static let latitudeKey = "weather.latitude"
    private static let longitudeKey = "weather.longitude"
    private static let cityKey = "weather.city"
    private static let notesKey = "weather.notes"
    private static let fetchedKey = "weather.fetched"
    private static let lastSnowKey = "weather.lastSnow"

    private(set) var enabled: Bool
    private(set) var city: String?
    private(set) var markLight: URL?
    private(set) var markDark: URL?
    private(set) var legal: URL?

    private let defaults = UserDefaults.standard

    private init() {
        enabled = defaults.bool(forKey: Self.enabledKey)
        city = defaults.string(forKey: Self.cityKey)
    }

    var available: Bool {
        Remote.shared.isOn(.weather)
    }

    private var location: CLLocation? {
        guard defaults.object(forKey: Self.latitudeKey) != nil else { return nil }
        return CLLocation(latitude: defaults.double(forKey: Self.latitudeKey), longitude: defaults.double(forKey: Self.longitudeKey))
    }

    func notes(after now: Date) -> [WeatherNote] {
        guard enabled, available, let data = defaults.data(forKey: Self.notesKey),
              let notes = try? JSONDecoder().decode([WeatherNote].self, from: data) else { return [] }
        return notes.filter { $0.fireDate > now }
    }

    func setEnabled(_ on: Bool) async {
        enabled = on
        defaults.set(on, forKey: Self.enabledKey)
        if on, location == nil {
            _ = await useCurrentLocation()
        }
        await refresh(force: true)
    }

    @discardableResult
    func useCurrentLocation() async -> Bool {
        guard let current = await LocationService.shared.currentLocation() else { return false }
        let mark = try? await CLGeocoder().reverseGeocodeLocation(current).first
        save(current.coordinate, name: mark?.locality ?? mark?.name)
        return true
    }

    func search(_ query: String) async -> [CLPlacemark] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return [] }
        let found = (try? await CLGeocoder().geocodeAddressString(text)) ?? []
        return found.filter { $0.location != nil }
    }

    func choose(_ mark: CLPlacemark) {
        guard let coordinate = mark.location?.coordinate else { return }
        save(coordinate, name: mark.locality ?? mark.name)
        Task { await refresh(force: true) }
    }

    private func save(_ coordinate: CLLocationCoordinate2D, name: String?) {
        defaults.set(coordinate.latitude, forKey: Self.latitudeKey)
        defaults.set(coordinate.longitude, forKey: Self.longitudeKey)
        defaults.set(name, forKey: Self.cityKey)
        city = name
    }

    func loadAttribution() async {
        guard markLight == nil, let attribution = try? await WeatherService.shared.attribution else { return }
        markLight = attribution.combinedMarkLightURL
        markDark = attribution.combinedMarkDarkURL
        legal = attribution.legalPageURL
    }

    // Asked again at most every three hours; the forecast does not change faster than that.
    func refresh(force: Bool = false) async {
        defer { Notifier.shared.scheduleSoon() }
        guard enabled, available, let location else {
            defaults.removeObject(forKey: Self.notesKey)
            return
        }
        let now = Date()
        if !force, let fetched = defaults.object(forKey: Self.fetchedKey) as? Date, now.timeIntervalSince(fetched) < 3 * 3600 {
            return
        }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now)) ?? now
        let end = calendar.date(byAdding: .day, value: 4, to: calendar.startOfDay(for: now)) ?? now
        guard let days = try? await WeatherService.shared.weather(for: location, including: .daily(startDate: start, endDate: end)) else { return }
        let forecast = days.map { Self.forecast($0, calendar: calendar) }
        let today = LocalDate(now, in: calendar)
        var lastSnow = (defaults.string(forKey: Self.lastSnowKey)).flatMap(Self.date)
        for day in forecast where day.day <= today && day.sky == .snow && day.precipitationChance >= 0.5 {
            if lastSnow.map({ day.day > $0 }) ?? true {
                lastSnow = day.day
            }
        }
        if let lastSnow {
            defaults.set(Self.text(lastSnow), forKey: Self.lastSnowKey)
        }
        let notes = compose(forecast, today: today, now: now, lastSnow: lastSnow, calendar: calendar)
        defaults.set(try? JSONEncoder().encode(notes), forKey: Self.notesKey)
        defaults.set(now, forKey: Self.fetchedKey)
    }

    private func compose(_ forecast: [DayForecast], today: LocalDate, now: Date, lastSnow: LocalDate?, calendar: Calendar) -> [WeatherNote] {
        let settings = Store.shared.settings
        let thresholds = WeatherThresholds(
            rainChance: Remote.shared.number(.weatherRainChance),
            wind: Remote.shared.number(.weatherWind),
            cold: Remote.shared.number(.weatherCold),
            heat: Remote.shared.number(.weatherHeat),
            drop: Remote.shared.number(.weatherDrop)
        )
        // Yesterday's snow decides "first snow" for today and tomorrow, not the forecast itself.
        let snowBefore = lastSnow.flatMap { $0 < today ? $0 : nil }
        var notes: [WeatherNote] = []
        for offset in 0...1 {
            let day = today.adding(days: offset)
            let next = day.adding(days: 1)
            if let fire = moment(day, settings.morning, calendar), fire > now,
               let event = WeatherRules.event(for: day, forecast: forecast, lastSnow: snowBefore, thresholds: thresholds) {
                notes.append(note(event, tomorrow: false, at: fire))
            }
            if let fire = moment(day, settings.evening, calendar), fire > now,
               let event = WeatherRules.event(for: next, forecast: forecast, lastSnow: snowBefore, thresholds: thresholds) {
                notes.append(note(event, tomorrow: true, at: fire))
            }
        }
        return notes
    }

    private func moment(_ day: LocalDate, _ time: LocalTime, _ calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute))
    }

    private func note(_ event: WeatherEvent, tomorrow: Bool, at fire: Date) -> WeatherNote {
        let locale = AppLanguage.current.locale
        func degrees(_ value: Double) -> String {
            Measurement(value: value, unit: UnitTemperature.celsius).formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
        }
        func difference(_ value: Double) -> String {
            let fahrenheit = locale.measurementSystem == .us
            return "\(Int((fahrenheit ? value * 9 / 5 : value).rounded()))°"
        }
        let title: String
        let body: String
        switch event {
        case .storm:
            title = tomorrow ? String(localized: "Thunderstorm tomorrow") : String(localized: "Thunderstorm today")
            body = String(localized: "Take an umbrella and take care outside.")
        case .firstSnow:
            title = tomorrow ? String(localized: "First snow tomorrow") : String(localized: "First snow today")
            body = String(localized: "Dress warmer and enjoy it.")
        case .snow:
            title = tomorrow ? String(localized: "Snow tomorrow") : String(localized: "Snow today")
            body = String(localized: "Dress warmer and leave a little earlier.")
        case .rain:
            title = tomorrow ? String(localized: "Rain tomorrow") : String(localized: "Rain today")
            body = String(localized: "Don't forget an umbrella.")
        case .wind(let speed):
            let gusts = Measurement(value: speed, unit: UnitSpeed.metersPerSecond).formatted(.measurement(width: .abbreviated, usage: .wind, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
            title = tomorrow ? String(localized: "Strong wind tomorrow") : String(localized: "Strong wind today")
            body = String(localized: "Gusts up to \(gusts).")
        case .frost(let low):
            title = tomorrow ? String(localized: "Frost tomorrow") : String(localized: "Frost today")
            body = String(localized: "Down to \(degrees(low)), dress warmer.")
        case .heat(let high):
            title = tomorrow ? String(localized: "Heat tomorrow") : String(localized: "Heat today")
            body = String(localized: "Up to \(degrees(high)), drink more water.")
        case .colder(let drop):
            title = tomorrow ? String(localized: "Colder tomorrow") : String(localized: "Colder today")
            body = String(localized: "\(difference(drop)) colder than the day before.")
        case .sunAfterRain:
            title = tomorrow ? String(localized: "Sun tomorrow") : String(localized: "Sun today")
            body = String(localized: "Finally, after the rainy days.")
        case .warmWeekend(let high):
            title = String(localized: "A warm weekend")
            body = String(localized: "Up to \(degrees(high)), a good time to get outside.")
        }
        return WeatherNote(fireDate: fire, title: title, body: body)
    }

    private static func forecast(_ day: DayWeather, calendar: Calendar) -> DayForecast {
        DayForecast(
            day: LocalDate(day.date, in: calendar),
            sky: sky(day),
            precipitationChance: day.precipitationChance,
            high: day.highTemperature.converted(to: .celsius).value,
            low: day.lowTemperature.converted(to: .celsius).value,
            wind: day.wind.speed.converted(to: .metersPerSecond).value
        )
    }

    private static func sky(_ day: DayWeather) -> DayForecast.Sky {
        switch day.condition {
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .tropicalStorm, .hurricane:
            return .storm
        case .snow, .heavySnow, .flurries, .sunFlurries, .blizzard, .blowingSnow:
            return .snow
        case .rain, .heavyRain, .drizzle, .sunShowers, .freezingRain, .freezingDrizzle, .hail, .sleet, .wintryMix:
            return .rain
        case .clear, .mostlyClear, .hot:
            return .clear
        default:
            switch day.precipitation {
            case .snow: return .snow
            case .rain, .sleet, .hail, .mixed: return .rain
            default: return .cloudy
            }
        }
    }

    private static func text(_ date: LocalDate) -> String {
        String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    }

    private static func date(_ text: String) -> LocalDate? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return LocalDate(year: parts[0], month: parts[1], day: parts[2])
    }
}
