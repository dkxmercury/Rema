import SwiftUI
import UIKit

enum AppIconChoice: String, CaseIterable, Identifiable {
    case mechanics
    case graphite
    case night
    case orange
    case olive
    case sand

    struct Look {
        let top: UInt32
        let bottom: UInt32
        let face: UInt32
        let ticks: UInt32
        let hand: UInt32
        let ring: Double
        let lightBody: Bool
    }

    var id: String { rawValue }

    var assetName: String? {
        switch self {
        case .mechanics: return nil
        case .graphite: return "AppIcon-Graphite"
        case .night: return "AppIcon-Night"
        case .orange: return "AppIcon-Orange"
        case .olive: return "AppIcon-Olive"
        case .sand: return "AppIcon-Sand"
        }
    }

    init(assetName: String?) {
        self = Self.allCases.first { $0.assetName == assetName } ?? .mechanics
    }

    var name: String {
        switch self {
        case .mechanics: return String(localized: "Mechanika", bundle: .app, locale: .app)
        case .graphite: return String(localized: "Graphite", bundle: .app, locale: .app)
        case .night: return String(localized: "Night", bundle: .app, locale: .app)
        case .orange: return String(localized: "Orange", bundle: .app, locale: .app)
        case .olive: return String(localized: "Olive", bundle: .app, locale: .app)
        case .sand: return String(localized: "Sand", bundle: .app, locale: .app)
        }
    }

    var note: String {
        switch self {
        case .mechanics: return String(localized: "the main one", bundle: .app, locale: .app)
        case .graphite: return String(localized: "dark body", bundle: .app, locale: .app)
        case .night: return String(localized: "orange ticks", bundle: .app, locale: .app)
        case .orange: return String(localized: "orange body", bundle: .app, locale: .app)
        case .olive: return String(localized: "green body", bundle: .app, locale: .app)
        case .sand: return String(localized: "warm and soft", bundle: .app, locale: .app)
        }
    }

    var look: Look {
        switch self {
        case .mechanics: return Look(top: 0xFBFAF8, bottom: 0xD6D2CB, face: 0xFBFAF8, ticks: 0x1C1B19, hand: 0xF26A1B, ring: 0.18, lightBody: true)
        case .graphite: return Look(top: 0x3A3835, bottom: 0x1C1B19, face: 0x262522, ticks: 0xF1EFEA, hand: 0xF26A1B, ring: 0.16, lightBody: false)
        case .night: return Look(top: 0x1A1918, bottom: 0x0B0A0A, face: 0x141312, ticks: 0xF26A1B, hand: 0xF7F6F3, ring: 0.20, lightBody: false)
        case .orange: return Look(top: 0xF58A45, bottom: 0xE05A12, face: 0xF7F6F3, ticks: 0x1C1B19, hand: 0x1C1B19, ring: 0.10, lightBody: true)
        case .olive: return Look(top: 0x5E7A4E, bottom: 0x3F5A33, face: 0xEEF0E6, ticks: 0x1C1B19, hand: 0xF26A1B, ring: 0.12, lightBody: false)
        case .sand: return Look(top: 0xE9DFCF, bottom: 0xCDBFA8, face: 0xF6F1E8, ticks: 0x5F5B55, hand: 0xB44A0A, ring: 0.14, lightBody: true)
        }
    }
}

@MainActor
@Observable
final class AppIcons {
    static let shared = AppIcons()

    private(set) var current: AppIconChoice

    var available: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    private init() {
        current = AppIconChoice(assetName: UIApplication.shared.alternateIconName)
    }

    func choose(_ choice: AppIconChoice) async -> Bool {
        guard choice != current else { return true }
        do {
            try await UIApplication.shared.setAlternateIconName(choice.assetName)
            current = choice
            return true
        } catch {
            return false
        }
    }
}
