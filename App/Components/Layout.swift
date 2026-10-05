import SwiftUI

struct RoundIconButton: View {
    let icon: [String]
    var iconSize: CGFloat = 18
    var lineWidth: CGFloat = 2
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RaisedCircle()
                Glyph(paths: icon, size: iconSize, lineWidth: lineWidth, color: Palette.text)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(label))
    }
}

struct ScreenHeader<Trailing: View>: View {
    enum Leading {
        case close
        case back
    }

    let title: LocalizedStringKey
    var leading: Leading = .back
    var action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            RoundIconButton(
                icon: leading == .close ? Icons.close : Icons.back,
                label: leading == .close ? "Close" : "Back",
                action: action
            )
            Spacer(minLength: 8)
            Text(title)
                .font(.app(.jost, 18, weight: 500))
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing()
                .frame(width: 44, height: 44)
        }
    }
}

extension ScreenHeader where Trailing == Color {
    init(title: LocalizedStringKey, leading: Leading = .back, action: @escaping () -> Void) {
        self.init(title: title, leading: leading, action: action) { Color.clear }
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
    }
}

struct PanelList<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .panel()
    }
}

struct Tag: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.app(.golos, 12, weight: 600))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 24)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .circular)
                    .strokeBorder(Palette.tagBorder, lineWidth: 1)
            }
    }
}

struct Chip: View {
    let title: LocalizedStringKey
    var selected = false
    var icon: [String]?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Glyph(paths: icon, size: 14, lineWidth: 2.4, color: selected ? Palette.onSegment : Palette.text)
                }
                Text(title)
                    .font(.app(.golos, 14, weight: 600))
            }
            .foregroundStyle(selected ? Palette.onSegment : Palette.text)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .circular)
                    .fill(selected ? Palette.segment : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .circular)
                    .strokeBorder(Palette.text, lineWidth: selected ? 0 : 1.5)
            }
        }
        .buttonStyle(PressableStyle())
        .animation(Motion.small, value: selected)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct PrimaryBar<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action, label: label)
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(.container, edges: .bottom)
    }
}
