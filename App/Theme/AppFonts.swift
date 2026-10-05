import CoreText
import SwiftUI

enum AppFonts {
    static func register() {
        for name in ["Jost-Variable", "GolosText-Variable"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

enum Typeface: String {
    case jost = "Jost"
    case golos = "Golos Text"
}

extension Font {
    static func app(_ face: Typeface, _ size: CGFloat, weight: Int = 400) -> Font {
        let weightAxis = NSNumber(value: 0x7767_6874)
        let attributes: [String: Any] = [
            kCTFontFamilyNameAttribute as String: face.rawValue,
            kCTFontVariationAttribute as String: [weightAxis: NSNumber(value: weight)],
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}
