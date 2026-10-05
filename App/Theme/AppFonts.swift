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

    nonisolated(unsafe) static var languageCode = Bundle.main.preferredLocalizations.first ?? "en"

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
