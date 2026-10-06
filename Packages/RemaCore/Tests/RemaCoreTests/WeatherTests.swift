import Foundation
import Testing
@testable import RemaCore

struct WeatherTests {
    let thresholds = WeatherThresholds(rainChance: 0.5, wind: 12, cold: -10, heat: 35, drop: 8)

    func day(_ number: Int) -> LocalDate {
        LocalDate(year: 2026, month: 10, day: number)
    }

    func forecast(_ number: Int, _ sky: DayForecast.Sky, chance: Double = 0.8, high: Double = 15, low: Double = 8, wind: Double = 4) -> DayForecast {
        DayForecast(day: day(number), sky: sky, precipitationChance: chance, high: high, low: low, wind: wind)
    }

    @Test func rainOnlyOnTheFirstWetDay() {
        let days = [forecast(5, .cloudy), forecast(6, .rain), forecast(7, .rain)]
        #expect(WeatherRules.event(for: day(6), forecast: days, lastSnow: nil, thresholds: thresholds) == .rain)
        #expect(WeatherRules.event(for: day(7), forecast: days, lastSnow: nil, thresholds: thresholds) == nil)
    }

    @Test func unlikelyRainStaysQuiet() {
        let days = [forecast(5, .cloudy), forecast(6, .rain, chance: 0.3)]
        #expect(WeatherRules.event(for: day(6), forecast: days, lastSnow: nil, thresholds: thresholds) == nil)
    }

    @Test func firstSnowIsSpecial() {
        let days = [forecast(5, .cloudy), forecast(6, .snow, high: 1, low: -3)]
        #expect(WeatherRules.event(for: day(6), forecast: days, lastSnow: nil, thresholds: thresholds) == .firstSnow)
        #expect(WeatherRules.event(for: day(6), forecast: days, lastSnow: day(1), thresholds: thresholds) == .snow)
    }

    @Test func extremesComeBeforeRain() {
        let days = [forecast(5, .cloudy), forecast(6, .rain, high: -5, low: -14)]
        #expect(WeatherRules.event(for: day(6), forecast: days, lastSnow: nil, thresholds: thresholds) == .frost(-14))
        let hot = [forecast(5, .clear, high: 30), forecast(6, .clear, high: 38)]
        #expect(WeatherRules.event(for: day(6), forecast: hot, lastSnow: nil, thresholds: thresholds) == .heat(38))
        let windy = [forecast(5, .clear), forecast(6, .cloudy, wind: 15)]
        #expect(WeatherRules.event(for: day(6), forecast: windy, lastSnow: nil, thresholds: thresholds) == .wind(15))
    }

    @Test func coldSnapAndSunAfterRain() {
        let snap = [forecast(5, .clear, high: 22), forecast(6, .cloudy, high: 12)]
        #expect(WeatherRules.event(for: day(6), forecast: snap, lastSnow: nil, thresholds: thresholds) == .colder(10))
        let sun = [forecast(4, .rain), forecast(5, .rain), forecast(6, .clear)]
        #expect(WeatherRules.event(for: day(6), forecast: sun, lastSnow: nil, thresholds: thresholds) == .sunAfterRain)
    }

    @Test func warmWeekend() {
        let weekend = [forecast(9, .clear, high: 21), forecast(10, .clear, high: 24), forecast(11, .clear, high: 23)]
        #expect(WeatherRules.event(for: day(10), forecast: weekend, lastSnow: nil, thresholds: thresholds) == .warmWeekend(24))
        #expect(WeatherRules.event(for: day(11), forecast: weekend, lastSnow: nil, thresholds: thresholds) == nil)
    }
}
