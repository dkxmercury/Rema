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

    // The text size chosen in iOS, capped so the screens built around the dial keep their shape. Widgets stay at 1.
    nonisolated(unsafe) static var scale: CGFloat = 1

    static func scale(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: 0.86
        case .small: 0.91
        case .medium: 0.96
        case .large: 1
        case .xLarge: 1.07
        case .xxLarge: 1.14
        case .xxxLarge: 1.2
        default: 1.26
        }
    }

    @discardableResult
    static func apply(_ size: DynamicTypeSize) -> Bool {
        scale = scale(for: size)
        return true
    }

    // Headlines and big numbers grow half as much as body text, they are large already.
    static func scaled(_ size: CGFloat) -> CGFloat {
        size * (size <= 20 ? scale : 1 + (scale - 1) / 2)
    }

    static func ctFont(_ face: Typeface, _ size: CGFloat, weight: Int, fixed: Bool = false) -> CTFont {
        let size = fixed ? size : scaled(size)
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
        let code = AppFonts.languageCode
        return Locale(identifier: code == "ar" ? "ar@numbers=latn" : code)
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

    // Text drawn inside the dial keeps its size whatever the iOS setting, the dial itself does not grow.
    static func appFixed(_ face: Typeface, _ size: CGFloat, weight: Int = 400) -> Font {
        Font(AppFonts.ctFont(face, size, weight: weight, fixed: true))
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

extension View {
    // As wide as «00:00» in the time font, so a larger text size or wider digits never break a time in two.
    func timeColumn(size: CGFloat = 18) -> some View {
        ZStack(alignment: .leading) {
            Text(verbatim: "00:00")
                .font(.app(.jost, size, weight: 600))
                .monospacedDigit()
                .hidden()
            lineLimit(1)
        }
    }
}
