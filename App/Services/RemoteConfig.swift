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
        case .support: "mailto:support@remaapp.cc"
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
        Localization.overrides = config.strings ?? [:]
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
        Localization.overrides = fresh.strings ?? [:]
    }

    func isOn(_ feature: Feature) -> Bool {
        config.features?[feature.rawValue] ?? true
    }

    func number(_ tunable: Tunable) -> Double {
        config.numbers?[tunable.rawValue] ?? tunable.standard
    }

    func link(_ key: LinkKey) -> URL {
        if key == .privacy || key == .terms || key == .site, AppLanguage.current == .russian, config.links?[key.rawValue] == nil {
            return URL(string: key.standard.replacingOccurrences(of: "remaapp.cc/", with: "remaapp.cc/ru/"))!
        }
        return URL(string: config.links?[key.rawValue] ?? key.standard) ?? URL(string: key.standard)!
    }

    func text(_ table: [String: String]?) -> String? {
        guard let table else { return nil }
        return table[AppLanguage.current.rawValue] ?? table["en"]
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

extension JSONDecoder {
    static var remote: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
