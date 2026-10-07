import Foundation
import Testing
@testable import RemaCore

struct PhraseParserGermanTests {
    let parser = PhraseParser(
        now: PhraseParserTests.now,
        calendar: PhraseParserTests.calendar,
        morning: LocalTime(hour: 9, minute: 0),
        evening: LocalTime(hour: 19, minute: 0),
        places: ["Zuhause", "Arbeit", "Fitnessstudio"],
        preferred: "de"
    )

    func when(_ phrase: ParsedPhrase) -> String? {
        guard let schedule = phrase.schedule else { return nil }
        return String(format: "%04d-%02d-%02d %02d:%02d", schedule.start.year, schedule.start.month, schedule.start.day, schedule.time.hour, schedule.time.minute)
    }

    @Test func tomorrowAtNine() {
        let result = parser.parse("morgen um 9 Mama anrufen")
        #expect(result.title == "Mama anrufen")
        #expect(when(result) == "2026-10-06 09:00")
    }

    @Test func offsets() {
        #expect(when(parser.parse("in 2 Stunden")) == "2026-10-05 15:50")
        let oven = parser.parse("in 20 Minuten Ofen ausschalten")
        #expect(when(oven) == "2026-10-05 14:10")
        #expect(oven.title == "Ofen ausschalten")
        #expect(when(parser.parse("in einer halben Stunde")) == "2026-10-05 14:20")
    }

    @Test func eveningAndWeekday() {
        let suit = parser.parse("am Freitag abends Anzug abholen")
        #expect(suit.title == "Anzug abholen")
        #expect(when(suit) == "2026-10-09 19:00")
        #expect(when(parser.parse("morgen abend Papa anrufen")) == "2026-10-06 19:00")
        let joined = parser.parse("am Freitagabend Anzug abholen")
        #expect(joined.title == "Anzug abholen")
        #expect(when(joined) == "2026-10-09 19:00")
        #expect(when(parser.parse("Dienstagmorgen Müll rausbringen")) == "2026-10-06 09:00")
    }

    @Test func repeats() {
        let running = parser.parse("jeden Dienstag und Donnerstag um 8 laufen")
        #expect(running.schedule?.rule == .weekly([.tuesday, .thursday]))
        #expect(when(running) == "2026-10-06 08:00")
        #expect(running.title == "Laufen")
        let birthday = parser.parse("jedes Jahr am 12. Oktober Geburtstag von Sascha")
        #expect(birthday.schedule?.rule == .yearly(month: 10, day: 12))
        #expect(birthday.title == "Geburtstag von Sascha")
        #expect(parser.parse("täglich um 9 Vitamine").schedule?.rule == .daily)
    }

    @Test func alertsFlagsAndPlaces() {
        let dentist = parser.parse("morgen um 15:00 Zahnarzt dringend eine Stunde vorher")
        #expect(dentist.urgent)
        #expect(dentist.preAlerts == [60])
        #expect(when(dentist) == "2026-10-06 15:00")
        let parcel = parser.parse("wenn ich die Arbeit verlasse Paket abholen")
        #expect(parcel.placeTrigger == .leave)
        #expect(parcel.placeNames == ["Arbeit"])
        #expect(parcel.title == "Paket abholen")
    }
}

struct PhraseParserFrenchTests {
    let parser = PhraseParser(
        now: PhraseParserTests.now,
        calendar: PhraseParserTests.calendar,
        morning: LocalTime(hour: 9, minute: 0),
        evening: LocalTime(hour: 19, minute: 0),
        places: ["Maison", "Travail", "Salle"],
        preferred: "fr"
    )

    func when(_ phrase: ParsedPhrase) -> String? {
        guard let schedule = phrase.schedule else { return nil }
        return String(format: "%04d-%02d-%02d %02d:%02d", schedule.start.year, schedule.start.month, schedule.start.day, schedule.time.hour, schedule.time.minute)
    }

    @Test func tomorrowAtNine() {
        let result = parser.parse("demain à 9h appeler maman")
        #expect(result.title == "Appeler maman")
        #expect(when(result) == "2026-10-06 09:00")
        #expect(parser.parse("rappelle-moi d'appeler maman demain à 9h").title == "Appeler maman")
    }

    @Test func offsets() {
        #expect(when(parser.parse("dans 2 heures")) == "2026-10-05 15:50")
        let oven = parser.parse("dans 20 minutes éteindre le four")
        #expect(when(oven) == "2026-10-05 14:10")
        #expect(oven.title == "Éteindre le four")
    }

    @Test func eveningAndWeekday() {
        let suit = parser.parse("vendredi soir récupérer le costume")
        #expect(suit.title == "Récupérer le costume")
        #expect(when(suit) == "2026-10-09 19:00")
        #expect(when(parser.parse("ce soir à 9h appeler papa")) == "2026-10-05 21:00")
    }

    @Test func repeats() {
        let running = parser.parse("tous les mardis et jeudis à 8h courir")
        #expect(running.schedule?.rule == .weekly([.tuesday, .thursday]))
        #expect(when(running) == "2026-10-06 08:00")
        #expect(running.title == "Courir")
        let birthday = parser.parse("tous les ans le 12 octobre anniversaire de Sacha")
        #expect(birthday.schedule?.rule == .yearly(month: 10, day: 12))
        #expect(birthday.title == "Anniversaire de Sacha")
        #expect(parser.parse("tous les jours à 9h vitamines").schedule?.rule == .daily)
    }

    @Test func alertsFlagsAndPlaces() {
        let dentist = parser.parse("demain à 15h dentiste urgent une heure avant")
        #expect(dentist.urgent)
        #expect(dentist.preAlerts == [60])
        #expect(when(dentist) == "2026-10-06 15:00")
        let parcel = parser.parse("quand je quitte le travail récupérer le colis")
        #expect(parcel.placeTrigger == .leave)
        #expect(parcel.placeNames == ["Travail"])
        #expect(parcel.title == "Récupérer le colis")
    }

    @Test func englishIsStillEnglish() {
        #expect(parser.parse("tomorrow at 9 call mom").title == "Call mom")
    }
}
