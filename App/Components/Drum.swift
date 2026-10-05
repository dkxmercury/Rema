import SwiftUI

struct Drum: View {
    let values: [Int]
    @Binding var selection: Int
    var height: CGFloat = 212
    @State private var position: Int?

    nonisolated static let row: CGFloat = 43

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(values, id: \.self) { value in
                    Text(verbatim: String(format: "%02d", value))
                        .font(.app(.jost, 44, weight: 500))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .frame(height: Drum.row)
                        .visualEffect { content, proxy in
                            let frame = proxy.frame(in: .scrollView)
                            let visible = proxy.bounds(of: .scrollView)?.height ?? 212
                            let offset = (frame.midY - visible / 2) / Drum.row
                            let distance = min(abs(offset), 3)
                            return content
                                .scaleEffect(Drum.scale(distance))
                                .offset(y: -(offset < 0 ? -1 : 1) * max(0, distance - 1) * 10)
                                .opacity(Drum.opacity(distance))
                        }
                        .id(value)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.vertical, (height - Drum.row) / 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position)
        .frame(height: height)
        .onAppear { position = selection }
        .onChange(of: position) { _, value in
            if let value, value != selection {
                selection = value
            }
        }
        .onChange(of: selection) { _, value in
            if position != value {
                withAnimation(Motion.standard) { position = value }
            }
        }
        .sensoryFeedback(trigger: position) { _, _ in Feedback.hapticsEnabled ? .selection : nil }
    }

    nonisolated static func scale(_ distance: CGFloat) -> CGFloat {
        if distance <= 1 { return 1 - distance * (1 - 26.0 / 44.0) }
        return 26.0 / 44.0 - min(distance - 1, 1) * ((26.0 - 22.0) / 44.0)
    }

    nonisolated static func opacity(_ distance: CGFloat) -> Double {
        if distance <= 1 { return 1 - distance * 0.31 }
        return max(0, 0.69 - min(distance - 1, 1) * 0.31 - max(distance - 2, 0) * 0.38)
    }
}
