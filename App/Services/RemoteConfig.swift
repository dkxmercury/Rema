import Foundation
import Observation
import RemaCore

struct RemoteConfig: Codable, Equatable {
    struct Announcement: Codable, Equatable {
        var id: String
        var title: [String: String]?
        var text: [String: String]
        var link: String?
        var until: Date?
    }

    var minimumVersion: String?
    var update: [String: String]?
    var announcement: Announcement?
    var features: [String: Bool]?
    var numbers: [String: Double]?
    var links: [String: String]?
    var phrases: [String: [String]]?
    var strings: [String: [String: String]]?
    var words: [String: [String: String]]?

    static let empty = RemoteConfig()
}

// Everything in the build is on by default and the reviewer sees it; the server can only switch features off or tune them.
enum Feature: String {
    case sync
    case realtime
    case liveActivity
    case voice
    case places
    case weather
    case tips
    case missed
    case suggestions
}

enum Tunable: String {
    case liveActivityLead
    case syncInterval
    case missedFollowUp
    case weatherRainChance
    case weatherWind
    case weatherCold
    case weatherHeat
    case weatherDrop

    var standard: Double {
        switch self {
        case .liveActivityLead: 60
        case .syncInterval: 60
        case .missedFollowUp: 30
        case .weatherRainChance: 0.5
        case .weatherWind: 12
        case .weatherCold: -10
        case .weatherHeat: 35
        case .weatherDrop: 8
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .liveActivityLead: 5...240
        case .syncInterval: 15...3600
        case .missedFollowUp: 5...240
        case .weatherRainChance: 0.2...0.95
        case .weatherWind: 5...40
        case .weatherCold: -50...10
        case .weatherHeat: 20...55
        case .weatherDrop: 3...30
        }
    }
}

enum LinkKey: String {
    case instagram
    case support
    case site
    case privacy
    case terms
    case appStore

    var standard: String {
        switch self {
        case .instagram: "https://www.instagram.com/rema.apps/"
        case .support: "https://remaapp.cc/support/"
        case .site: "https://remaapp.cc/"
        case .privacy: "https://remaapp.cc/privacy/"
        case .terms: "https://remaapp.cc/terms/"
        case .appStore: "https://apps.apple.com/app/id6819110559"
        }
    }
}

@MainActor
@Observable
final class Remote {
    static let shared = Remote()

    private(set) var config: RemoteConfig
    @ObservationIgnored private var fetchedAt: Date?

    private static var cacheURL: URL {
        SharedStore.localDirectory.appendingPathComponent("remote-config.json")
    }

    private init() {
        config = (try? JSONDecoder.remote.decode(RemoteConfig.self, from: Data(contentsOf: Self.cacheURL))) ?? .empty
        Localization.overrides = Self.checked(config.strings)
    }

    func refresh(force: Bool = false) async {
        if !force, let fetchedAt, Date().timeIntervalSince(fetchedAt) < 15 * 60 { return }
        guard let data = try? await Backend.raw("GET", "/api/rema/config"),
              let fresh = try? JSONDecoder.remote.decode(RemoteConfig.self, from: data) else { return }
        fetchedAt = Date()
        try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.cacheURL, options: .atomic)
        guard fresh != config else { return }
        config = fresh
        Localization.overrides = Self.checked(fresh.strings)
    }

    func isOn(_ feature: Feature) -> Bool {
        config.features?[feature.rawValue] ?? true
    }

    func number(_ tunable: Tunable) -> Double {
        guard let value = config.numbers?[tunable.rawValue], value.isFinite else { return tunable.standard }
        return min(max(value, tunable.range.lowerBound), tunable.range.upperBound)
    }

    func link(_ key: LinkKey) -> URL {
        if let text = config.links?[key.rawValue], let url = URL(string: text), url.scheme == "https", url.host() != nil {
            return url
        }
        if key != .instagram, key != .appStore, AppLanguage.current == .russian {
            return URL(string: key.standard.replacingOccurrences(of: "remaapp.cc/", with: "remaapp.cc/ru/"))!
        }
        return URL(string: key.standard)!
    }

    func text(_ table: [String: String]?) -> String? {
        guard let table else { return nil }
        return table[AppLanguage.current.rawValue] ?? table["en"]
    }

    // Words the server teaches the phrase reader, «сёдня» for «сегодня»; only plain words get through.
    var words: [String: String] {
        var merged: [String: String] = [:]
        for table in (config.words ?? [:]).values {
            for (variant, meaning) in table.prefix(500) where (1...30).contains(variant.count) && (1...40).contains(meaning.count)
                && variant.allSatisfy({ $0.isLetter || $0 == "'" }) && meaning.allSatisfy({ $0.isLetter || $0 == " " || $0 == "'" }) {
                merged[variant.lowercased()] = meaning.lowercased()
            }
        }
        return merged
    }

    var exampleOverride: [String]? {
        config.phrases?[AppLanguage.current.rawValue]
    }

    var needsUpdate: Bool {
        guard let minimum = config.minimumVersion,
              let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return false }
        return current.compare(minimum, options: .numeric) == .orderedAscending
    }

    var activeAnnouncement: RemoteConfig.Announcement? {
        guard let announcement = config.announcement, text(announcement.text) != nil else { return nil }
        if let until = announcement.until, until < Date() { return nil }
        return announcement
    }
}

extension Remote {
    // A fix whose placeholders differ from the key would break String(format:), so it is dropped.
    private static func checked(_ strings: [String: [String: String]]?) -> [String: [String: String]] {
        (strings ?? [:]).mapValues { table in
            table.filter { key, value in placeholders(key) == placeholders(value) }
        }
    }

    private static let placeholder = try? NSRegularExpression(pattern: "%(?:[0-9]+[$])?[-+ #0']*[0-9]*(?:[.][0-9]+)?(hh|h|ll|l|q|L|z|t|j)?([@dDuUxXoOfFeEgGcCsSpaA%])")

    private static func placeholders(_ text: String) -> [String] {
        guard let placeholder else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return placeholder.matches(in: text, range: range).compactMap { match in
            let conversion = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            guard conversion != "%" else { return nil }
            let length = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
            return length + conversion
        }
        .sorted()
    }
}

extension JSONDecoder {
    static var remote: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
