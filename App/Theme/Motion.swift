import SwiftUI

enum Motion {
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.82)
    static let small = Animation.spring(response: 0.28, dampingFraction: 0.75)
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.9)
    static let hand = Animation.spring(response: 0.9, dampingFraction: 0.78)
}
