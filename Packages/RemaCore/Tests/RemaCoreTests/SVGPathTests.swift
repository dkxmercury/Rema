import Testing
@testable import RemaCore

struct SVGPathTests {
    @Test func movesAndRelativeLines() {
        let segments = SVGPath.parse("M12 5v14M5 12h14")
        #expect(segments == [
            .move(SVGPoint(12, 5)),
            .line(SVGPoint(12, 19)),
            .move(SVGPoint(5, 12)),
            .line(SVGPoint(19, 12)),
        ])
    }

    @Test func compactNumbers() {
        let segments = SVGPath.parse("M12 3.5l2.6 5.3 5.9.9")
        #expect(segments.count == 3)
        guard case .line(let last) = segments[2] else {
            Issue.record("ожидалась линия")
            return
        }
        #expect(abs(last.x - 20.5) < 1e-9)
        #expect(abs(last.y - 9.7) < 1e-9)
    }

    @Test func implicitLinesAfterMove() {
        let segments = SVGPath.parse("M5 12.5l4.5 4.5L19 7.5")
        #expect(segments == [
            .move(SVGPoint(5, 12.5)),
            .line(SVGPoint(9.5, 17)),
            .line(SVGPoint(19, 7.5)),
        ])
    }

    @Test func smoothCubicReflectsControl() {
        let segments = SVGPath.parse("M0 0C0 10 10 10 10 0s10-10 10 0")
        guard segments.count == 3, case .cubic(let control1, _, let end) = segments[2] else {
            Issue.record("ожидалась вторая кривая")
            return
        }
        #expect(control1 == SVGPoint(10, -10))
        #expect(end == SVGPoint(20, 0))
    }

    @Test func halfCircleArcGoesOverTheTop() {
        let segments = SVGPath.parse("M0 0A10 10 0 0 1 20 0")
        #expect(segments.count == 3)
        guard case .cubic(_, _, let middle) = segments[1], case .cubic(_, _, let end) = segments[2] else {
            Issue.record("ожидались две кривые")
            return
        }
        #expect(abs(middle.x - 10) < 1e-9)
        #expect(abs(middle.y + 10) < 1e-9)
        #expect(end == SVGPoint(20, 0))
    }

    @Test func compactArcFlags() {
        let spaced = SVGPath.parse("M5.5 9.8a6.5 6.5 0 0 1 13 0")
        let packed = SVGPath.parse("M5.5 9.8a6.5 6.5 0 0113 0")
        #expect(spaced == packed)
        #expect(spaced.count >= 3)
    }

    @Test func closeReturnsToStart() {
        let segments = SVGPath.parse("M2 2h4v4zl1 1")
        #expect(segments.last == .line(SVGPoint(3, 3)))
    }
}
