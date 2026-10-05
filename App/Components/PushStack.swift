import SwiftUI

struct PushStack<Route: Hashable, Root: View, Destination: View>: View {
    @Binding var path: [Route]
    @ViewBuilder var root: () -> Root
    @ViewBuilder var destination: (Route) -> Destination
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                root()
                    .offset(x: path.isEmpty ? 0 : (reduceMotion ? 0 : -width * 0.3 + drag * 0.3))
                    .allowsHitTesting(path.isEmpty)
                ForEach(Array(path.enumerated()), id: \.element) { index, route in
                    let isTop = index == path.count - 1
                    destination(route)
                        .background(Palette.background.ignoresSafeArea())
                        .offset(x: isTop ? drag : 0)
                        .shadow(color: .black.opacity(isTop && drag > 0 ? 0.12 : 0), radius: 16, x: -6)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                        .zIndex(Double(index + 1))
                        .simultaneousGesture(isTop ? edgeSwipe(width: width) : nil)
                }
            }
            .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: path)
        }
    }

    private func edgeSwipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard value.startLocation.x < 28 else { return }
                drag = max(0, value.translation.width)
            }
            .onEnded { value in
                guard value.startLocation.x < 28 else { return }
                if value.predictedEndTranslation.width > width * 0.5 || value.translation.width > width * 0.35 {
                    withAnimation(Motion.standard) {
                        path.removeLast()
                        drag = 0
                    }
                } else {
                    withAnimation(Motion.standard) { drag = 0 }
                }
            }
    }
}
