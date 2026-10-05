import SwiftUI

enum Motion {
    static let standard = Animation.spring(duration: 0.4, bounce: 0)
    static let small = Animation.snappy(duration: 0.3, extraBounce: 0.1)
    static let press = Animation.spring(duration: 0.18, bounce: 0)
    static let hand = Animation.spring(duration: 0.9, bounce: 0.2)
    static let appear = Animation.smooth(duration: 0.35)
    static let fade = Animation.easeOut(duration: 0.2)

    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }
}
