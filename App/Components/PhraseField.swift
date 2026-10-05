import SwiftUI
import UIKit

struct PhraseField: UIViewRepresentable {
    @Binding var text: String
    var highlights: [Range<Int>]
    var pending: Range<Int>?
    var editable: Bool
    @Binding var focused: Bool
    var onSubmit: () -> Void

    init(
        text: Binding<String>,
        highlights: [Range<Int>],
        pending: Range<Int>? = nil,
        editable: Bool = true,
        focused: Binding<Bool> = .constant(false),
        onSubmit: @escaping () -> Void = {}
    ) {
        _text = text
        self.highlights = highlights
        self.pending = pending
        self.editable = editable
        _focused = focused
        self.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PhraseTextView {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        let view = PhraseTextView(frame: .zero, textContainer: container)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: PhraseTextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = editable
        view.isSelectable = editable
        view.apply(text: text, highlights: highlights, pending: pending)
        guard editable else { return }
        if focused, !view.isFirstResponder {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        } else if !focused, view.isFirstResponder {
            DispatchQueue.main.async { view.resignFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PhraseTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PhraseField

        init(_ parent: PhraseField) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            parent.onSubmit()
            return false
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.focused {
                parent.focused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.focused {
                parent.focused = false
            }
        }
    }
}

final class PhraseTextView: UITextView {
    private let face = UIFont.app(.golos, 24, weight: 600)
    private let lineHeight: CGFloat = 32
    private var marks: [NSRange] = []
    private var markStarts: [NSRange: CFTimeInterval] = [:]
    private var applied: (text: String, highlights: [Range<Int>], pending: Range<Int>?)?
    private var link: CADisplayLink?
    private let markDuration: CFTimeInterval = 0.28

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        backgroundColor = .clear
        isScrollEnabled = false
        textContainerInset = .zero
        tintColor = UIPalette.accent
        returnKeyType = .done
        autocapitalizationType = .sentences
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        typingAttributes = baseAttributes
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        return [
            .font: face,
            .foregroundColor: UIPalette.text,
            .paragraphStyle: paragraph,
            .baselineOffset: (lineHeight - glyphHeight) / 2,
        ]
    }

    private var glyphHeight: CGFloat {
        face.ascender - face.descender
    }

    func apply(text newText: String, highlights: [Range<Int>], pending: Range<Int>?) {
        if let applied, applied.text == newText, applied.highlights == highlights, applied.pending == pending {
            return
        }
        if text != newText {
            text = newText
        }
        guard markedTextRange == nil else { return }
        applied = (newText, highlights, pending)
        let whole = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes, range: whole)
        if let pending, let range = characterRange(pending) {
            textStorage.addAttribute(.foregroundColor, value: UIPalette.secondary, range: range)
        }
        textStorage.endEditing()
        typingAttributes = baseAttributes
        let now = CACurrentMediaTime()
        let updated = highlights.compactMap(characterRange)
        var starts: [NSRange: CFTimeInterval] = [:]
        for mark in updated {
            starts[mark] = markStarts[mark] ?? (window == nil ? 0 : now)
        }
        markStarts = starts
        marks = updated
        if starts.values.contains(where: { now - $0 < markDuration }) {
            startLink()
        }
        setNeedsDisplay()
    }

    private func startLink() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step() {
        setNeedsDisplay()
        let now = CACurrentMediaTime()
        if !markStarts.values.contains(where: { now - $0 < markDuration }) {
            link?.invalidate()
            link = nil
        }
    }

    override func removeFromSuperview() {
        link?.invalidate()
        link = nil
        super.removeFromSuperview()
    }

    private func characterRange(_ range: Range<Int>) -> NSRange? {
        let string = text ?? ""
        guard range.lowerBound >= 0, range.upperBound <= string.count, !range.isEmpty else { return nil }
        let start = string.index(string.startIndex, offsetBy: range.lowerBound)
        let end = string.index(start, offsetBy: range.count)
        return NSRange(start..<end, in: string)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard !marks.isEmpty, let context = UIGraphicsGetCurrentContext() else { return }
        let height = glyphHeight
        let underline = UIPalette.accent.cgColor
        let inset = textContainerInset
        let now = CACurrentMediaTime()
        for range in marks {
            let elapsed = now - (markStarts[range] ?? 0)
            let linear = min(1, max(0, elapsed / markDuration))
            let eased = 1 - pow(1 - linear, 3)
            let fill = UIPalette.accent.withAlphaComponent(0.18 * eased).cgColor
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { box, _ in
                let frame = CGRect(x: box.minX + inset.left, y: box.midY + inset.top - height / 2, width: box.width, height: height)
                context.saveGState()
                context.addPath(UIBezierPath(roundedRect: frame, cornerRadius: 6).cgPath)
                context.clip()
                context.setFillColor(fill)
                context.fill(frame)
                context.setFillColor(underline)
                context.fill(CGRect(x: frame.minX, y: frame.maxY - 2, width: frame.width * eased, height: 2))
                context.restoreGState()
            }
        }
    }
}
