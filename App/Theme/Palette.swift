import SwiftUI
import UIKit

enum Palette {
    static let background = Color(light: 0xECEAE5, dark: 0x1A1918)
    static let panel = Color(light: 0xF7F6F3, dark: 0x262522)
    static let text = Color(uiColor: UIPalette.text)
    static let secondary = Color(uiColor: UIPalette.secondary)
    static let hairline = Color(light: 0x1C1B19, lightAlpha: 0.10, dark: 0xF1EFEA, darkAlpha: 0.10)

    static let accent = Color(hex: 0xF26A1B)
    static let onAccent = Color(hex: 0x1C1B19)
    static let accentText = Color(light: 0xB44A0A, dark: 0xF7924F)
    static let accentTextOnBackground = Color(light: 0xAE470A, dark: 0xF7924F)
    static let accentOnDark = Color(hex: 0xF7924F)
    static let urgent = Color(hex: 0xC0341D)
    static let urgentIcon = Color(light: 0xC0341D, dark: 0xFF7A63)
    static let urgentText = Color(light: 0xC0341D, dark: 0xFF8E7A)
    static let yearly = Color(light: 0x3F7D3A, dark: 0x7FB86F)
    static let granted = Color(light: 0x2F6A2B, dark: 0x7FB86F)

    static let panelHighlight = Color(light: 0xFFFFFF, lightAlpha: 0.9, dark: 0xFFFFFF, darkAlpha: 0.05)
    static let panelShadowNear = Color(light: 0x1C1B19, lightAlpha: 0.08, dark: 0x000000, darkAlpha: 0.45)
    static let panelShadowFar = Color(light: 0x1C1B19, lightAlpha: 0.06, dark: 0x000000, darkAlpha: 0.35)
    static let barShadowNear = Color(light: 0x1C1B19, lightAlpha: 0.10, dark: 0x000000, darkAlpha: 0.5)
    static let barShadowFar = Color(light: 0x1C1B19, lightAlpha: 0.10, dark: 0x000000, darkAlpha: 0.4)

    static let raisedTop = Color(light: 0xFBFAF8, dark: 0x34322F)
    static let raisedBottom = Color(light: 0xE6E3DD, dark: 0x242321)
    static let raisedHighlight = Color(light: 0xFFFFFF, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let raisedShadowNear = Color(light: 0x1C1B19, lightAlpha: 0.14, dark: 0x000000, darkAlpha: 0.5)
    static let raisedShadowFar = Color(light: 0x1C1B19, lightAlpha: 0.08, dark: 0x000000, darkAlpha: 0.3)

    static let segment = Color(light: 0x1C1B19, dark: 0xF1EFEA)
    static let onSegment = Color(light: 0xF7F6F3, dark: 0x1C1B19)
    static let segmentShadow = Color(light: 0x1C1B19, lightAlpha: 0.25, dark: 0x000000, darkAlpha: 0.5)
    static let segmentWell = Color(light: 0x1C1B19, lightAlpha: 0.12, dark: 0x000000, darkAlpha: 0.5)
    static let track = Color(light: 0xE3E0DA, dark: 0x1E1D1B)
    static let tagBorder = Color(light: 0x1C1B19, lightAlpha: 0.25, dark: 0xF1EFEA, darkAlpha: 0.25)
    static let radioBorder = Color(light: 0x1C1B19, lightAlpha: 0.22, dark: 0xF1EFEA, darkAlpha: 0.22)
    static let faint = Color(light: 0xA39E95, dark: 0x5F5B55)
    static let timelineLine = Color(hex: 0xF26A1B, alpha: 0.40)

    static let well = Color(light: 0xFBFAF8, dark: 0x1E1D1B)
    static let wellBorder = Color(light: 0x1C1B19, lightAlpha: 0.18, dark: 0xF1EFEA, darkAlpha: 0.20)
    static let wellShadow = Color(light: 0x1C1B19, lightAlpha: 0.16, dark: 0x000000, darkAlpha: 0.5)

    static let dialBezelTop = Color(light: 0xFBFAF8, dark: 0x3A3835)
    static let dialBezelBottom = Color(light: 0xD9D5CE, dark: 0x1C1B19)
    static let dialBezelHighlight = Color(light: 0xFFFFFF, dark: 0xFFFFFF, darkAlpha: 0.10)
    static let dialShadowNear = Color(light: 0x1C1B19, lightAlpha: 0.12, dark: 0x000000, darkAlpha: 0.4)
    static let dialShadowFar = Color(light: 0x1C1B19, lightAlpha: 0.16, dark: 0x000000, darkAlpha: 0.5)
    static let dialFace = Color(light: 0xFBFAF8, dark: 0x232220)
    static let dialFaceShadow = Color(light: 0x1C1B19, lightAlpha: 0.14, dark: 0x000000, darkAlpha: 0.55)
    static let dialTick = Color(light: 0x1C1B19, dark: 0xF1EFEA)
    static let dialNumeral = Color(light: 0x3A3834, dark: 0xCFCAC2)
    static let dialDone = Color(light: 0xB5B0A8, dark: 0x5F5B55)
    static let dialUpcoming = Color(light: 0x1C1B19, dark: 0xF1EFEA)
    static let dialNextRing = Color(light: 0xFBFAF8, dark: 0x232220)
    static let dialCap = Color(light: 0x1C1B19, dark: 0xF1EFEA)
    static let dialWindow = Color(light: 0x1C1B19, dark: 0x0F0E0D)
    static let dialWindowText = Color(light: 0xF7F6F3, dark: 0xF1EFEA)
    static let dialWindowBorder = Color(light: 0x000000, lightAlpha: 0, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let miniFace = Color(light: 0xFBFAF8, dark: 0x232220)
    static let miniRim = Color(light: 0x1C1B19, lightAlpha: 0.14, dark: 0xF1EFEA, darkAlpha: 0.14)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    init(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor(light: light, lightAlpha: lightAlpha, dark: dark, darkAlpha: darkAlpha))
    }
}

enum UIPalette {
    static let text = UIColor(light: 0x1C1B19, dark: 0xF1EFEA)
    static let secondary = UIColor(light: 0x5F5B55, dark: 0xA8A29A)
    static let accent = UIColor(hex: 0xF26A1B)
}

extension UIColor {
    convenience init(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) {
        self.init { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        }
    }

    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
