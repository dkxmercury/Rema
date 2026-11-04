import SwiftUI

struct PriorityBadge: View {
    let number: Int
    var size: CGFloat = 22

    var body: some View {
        Text(verbatim: "\(number)")
            .font(.appFixed(.jost, size * 0.6, weight: 600))
            .foregroundStyle(Palette.accentOnSegment)
            .frame(width: size, height: size)
            .background(Circle().fill(Palette.segment))
            .accessibilityHidden(true)
    }
}
