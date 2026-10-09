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
    var latestVersion: String?
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
        if let words = try? JSONEncoder().encode(Self.checkedWords(fresh.words)) {
            try? words.write(to: Self.wordsURL, options: .atomic)
        }
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

    // A link from the server may only lead to our own places; a compromised config must not turn «Privacy» into a stranger's page.
    private static let trustedHosts = ["remaapp.cc", "apps.apple.com", "instagram.com", "t.me"]

    func link(_ key: LinkKey) -> URL {
        if let text = config.links?[key.rawValue], let url = URL(string: text), url.scheme == "https", let host = url.host()?.lowercased(),
           Self.trustedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
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

    // Words the server teaches the phrase reader, «сёдня» for «сегодня», by language; only plain words get through.
    var words: [String: [String: String]] {
        Self.checkedWords(config.words)
    }

    static func checkedWords(_ words: [String: [String: String]]?) -> [String: [String: String]] {
        var checked: [String: [String: String]] = [:]
        for (language, table) in words ?? [:] {
            for (variant, meaning) in table.prefix(500) where (1...30).contains(variant.count) && (1...40).contains(meaning.count)
                && variant.allSatisfy({ $0.isLetter || $0 == "'" }) && meaning.allSatisfy({ $0.isLetter || $0 == " " || $0 == "'" }) {
                checked[language, default: [:]][variant.lowercased()] = meaning.lowercased()
            }
        }
        return checked
    }

    // The share sheet reads the phrase too and cannot see the app's own files.
    static var wordsURL: URL {
        SharedStore.directory.appendingPathComponent("phrase-words.json")
    }

    var exampleOverride: [String]? {
        config.phrases?[AppLanguage.current.rawValue]
    }

    var needsUpdate: Bool {
        guard let minimum = config.minimumVersion,
              let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return false }
        return current.compare(minimum, options: .numeric) == .orderedAscending
    }

    // The version just out in the App Store, offered gently; the one below the minimum is asked for in an alert instead.
    var newerVersion: String? {
        guard !needsUpdate, let latest = config.latestVersion, latest.count <= 20, latest.allSatisfy({ $0.isNumber || $0 == "." }),
              let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              current.compare(latest, options: .numeric) == .orderedAscending else { return nil }
        return latest
    }

    var activeAnnouncement: RemoteConfig.Announcement? {
        guard let announcement = config.announcement, text(announcement.text) != nil else { return nil }
        if let until = announcement.until, until < Date() { return nil }
        return announcement
    }
}

extension Remote {
    // A fix whose placeholders differ from the key would break String(format:), so it is dropped.
    // Strings with links inside stay as built; a fix could point them anywhere.
    private static func checked(_ strings: [String: [String: String]]?) -> [String: [String: String]] {
        (strings ?? [:]).mapValues { table in
            table.filter { key, value in placeholders(key) == placeholders(value) && !key.contains("](") && !value.contains("](") }
        }
    }

    private static let placeholder = try? NSRegularExpression(pattern: "%([0-9]+[$])?[-+ #0']*[0-9]*(?:[.][0-9]+)?(hh|h|ll|l|q|L|z|t|j)?([@dDuUxXoOfFeEgGcCsSpaAn%])")

    // Each argument with the type it is read as, in the order the arguments are taken; a fix must read every one the same way the key does.
    private static func placeholders(_ text: String) -> [String] {
        guard let placeholder else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var next = 1
        return placeholder.matches(in: text, range: range).compactMap { match in
            let conversion = Range(match.range(at: 3), in: text).map { String(text[$0]) } ?? ""
            guard conversion != "%" else { return nil }
            let length = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            let position = Range(match.range(at: 1), in: text).flatMap { Int(text[$0].dropLast()) } ?? next
            next = position + 1
            return "\(position):\(length)\(conversion)"
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
