import Foundation
import ObjectiveC
import SwiftUI
import WidgetKit

enum AppLanguage: String, CaseIterable, Identifiable {
    case russian = "ru"
    case english = "en"
    case ukrainian = "uk"
    case uzbekLatin = "uz-Latn"
    case uzbekCyrillic = "uz-Cyrl"
    case arabic = "ar"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    private static let storageKey = "appLanguage"

    nonisolated(unsafe) private(set) static var current: AppLanguage = saved ?? system

    private static var saved: AppLanguage? {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:))
    }

    static var system: AppLanguage {
        Locale.preferredLanguages.lazy.compactMap(match).first ?? .english
    }

    static func match(_ identifier: String) -> AppLanguage? {
        let lowered = identifier.lowercased()
        if lowered.hasPrefix("uz") {
            return lowered.contains("cyrl") ? .uzbekCyrillic : .uzbekLatin
        }
        let base = lowered.split(separator: "-").first.map(String.init) ?? lowered
        return allCases.first { $0.rawValue == base }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    // Xcode builds Uzbek Latin into uz.lproj, the Cyrillic one keeps its script in the name.
    var folder: String {
        self == .uzbekLatin ? "uz" : rawValue
    }

    var layoutDirection: LayoutDirection {
        self == .arabic ? .rightToLeft : .leftToRight
    }

    var nativeName: String {
        switch self {
        case .russian: "Русский"
        case .english: "English"
        case .ukrainian: "Українська"
        case .uzbekLatin: "O‘zbekcha"
        case .uzbekCyrillic: "Ўзбекча"
        case .arabic: "العربية"
        case .french: "Français"
        case .german: "Deutsch"
        }
    }

    var localizedName: String {
        switch self {
        case .russian: String(localized: "Russian", bundle: .app, locale: .app)
        case .english: String(localized: "English", bundle: .app, locale: .app)
        case .ukrainian: String(localized: "Ukrainian", bundle: .app, locale: .app)
        case .uzbekLatin: String(localized: "Uzbek, Latin", bundle: .app, locale: .app)
        case .uzbekCyrillic: String(localized: "Uzbek, Cyrillic", bundle: .app, locale: .app)
        case .arabic: String(localized: "Arabic", bundle: .app, locale: .app)
        case .french: String(localized: "French", bundle: .app, locale: .app)
        case .german: String(localized: "German", bundle: .app, locale: .app)
        }
    }

    static func activate() {
        Localization.install()
        apply(current)
    }

    static func choose(_ language: AppLanguage) {
        current = language
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        apply(language)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func apply(_ language: AppLanguage) {
        Localization.selected = Bundle.main.path(forResource: language.folder, ofType: "lproj").flatMap(Bundle.init(path:))
        Localization.language = language.rawValue
        AppFonts.languageCode = language.rawValue
        Bundle.app = Localization.selected ?? .main
        AppFonts.shared?.set(language.rawValue, forKey: AppFonts.languageKey)
        AppFonts.shared?.set(language.folder, forKey: AppFonts.folderKey)
    }
}

// The phone keeps one language for every app and cannot tell the two Uzbek scripts apart,
// so app strings are read from the chosen language folder, with fixes from the remote settings on top.
enum Localization {
    nonisolated(unsafe) static var selected: Bundle?
    nonisolated(unsafe) static var language = "en"
    nonisolated(unsafe) static var overrides: [String: [String: String]] = [:]
    nonisolated(unsafe) private static var installed = false

    static func install() {
        guard !installed,
              let original = class_getInstanceMethod(Bundle.self, #selector(Bundle.localizedString(forKey:value:table:))),
              let replacement = class_getInstanceMethod(Bundle.self, #selector(Bundle.remaLocalizedString(forKey:value:table:)))
        else { return }
        method_exchangeImplementations(original, replacement)
        installed = true
    }
}

extension Bundle {
    @objc fileprivate func remaLocalizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard bundlePath.hasPrefix(Bundle.main.bundlePath), !bundlePath.hasSuffix(".appex") else {
            return remaLocalizedString(forKey: key, value: value, table: tableName)
        }
        if tableName == nil || tableName == "Localizable", let override = Localization.overrides[Localization.language]?[key] {
            return override
        }
        if self === Bundle.main, let selected = Localization.selected {
            return selected.remaLocalizedString(forKey: key, value: value, table: tableName)
        }
        return remaLocalizedString(forKey: key, value: value, table: tableName)
    }
}
