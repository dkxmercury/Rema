import CoreText
import SwiftUI
import UIKit

enum AppFonts {
    static func register() {
        for name in ["Jost-Variable", "GolosText-Variable"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // Extensions can't read the app's own settings, so the app copies its language into the shared group.
    static let shared = UserDefaults(suiteName: "group.uz.dkx.rema")
    static let languageKey = "app.language"
    static let folderKey = "app.languageFolder"

    nonisolated(unsafe) private static var chosenCode: String?

    // Without a choice made in this process it reads the group every time, a widget process can outlive a language change.
    static var languageCode: String {
        get { chosenCode ?? shared?.string(forKey: languageKey) ?? Bundle.main.preferredLocalizations.first ?? "en" }
        set { chosenCode = newValue }
    }

    static var direction: LayoutDirection {
        languageCode.hasPrefix("ar") ? .rightToLeft : .leftToRight
    }

    // Jost has no Ukrainian, Uzbek or Arabic letters, mixing fonts inside a word looks broken.
    static var jostCoversLanguage: Bool {
        !(languageCode.hasPrefix("uk") || languageCode.hasPrefix("uz") || languageCode.hasPrefix("ar"))
    }

    static func ctFont(_ face: Typeface, _ size: CGFloat, weight: Int) -> CTFont {
        let weightAxis = NSNumber(value: 0x7767_6874)
        let family = face == .jost && !jostCoversLanguage ? Typeface.golos.rawValue : face.rawValue
        let attributes: [String: Any] = [
            kCTFontFamilyNameAttribute as String: family,
            kCTFontVariationAttribute as String: [weightAxis: NSNumber(value: weight)],
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}

extension Locale {
    static var app: Locale {
        Locale(identifier: AppFonts.languageCode)
    }
}

// String(localized:) reads the table of the process language, not the one chosen in the app, so lookups go to the chosen folder.
extension Bundle {
    nonisolated(unsafe) private static var chosenApp: Bundle?

    static var app: Bundle {
        get {
            chosenApp ?? AppFonts.shared?.string(forKey: AppFonts.folderKey)
                .flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
                .flatMap(Bundle.init(path:)) ?? .main
        }
        set { chosenApp = newValue }
    }
}

extension View {
    func appLanguage() -> some View {
        environment(\.locale, .app).environment(\.layoutDirection, AppFonts.direction)
    }
}

enum Typeface: String {
    case jost = "Jost"
    case golos = "Golos Text"
}

extension Font {
    static func app(_ face: Typeface, _ size: CGFloat, weight: Int = 400) -> Font {
        Font(AppFonts.ctFont(face, size, weight: weight))
    }
}

extension View {
    func lineHeight(_ height: CGFloat, _ face: Typeface, _ size: CGFloat, weight: Int = 400) -> some View {
        let extra = height - UIFont.app(face, size, weight: weight).lineHeight
        return lineSpacing(max(extra, 0)).padding(.vertical, extra / 2)
    }

    func lineBox(_ height: CGFloat, _ face: Typeface, _ size: CGFloat, weight: Int = 400) -> some View {
        padding(.vertical, (height - UIFont.app(face, size, weight: weight).lineHeight) / 2)
    }
}

extension UIFont {
    static func app(_ face: Typeface, _ size: CGFloat, weight: Int = 400) -> UIFont {
        AppFonts.ctFont(face, size, weight: weight) as UIFont
    }
}
