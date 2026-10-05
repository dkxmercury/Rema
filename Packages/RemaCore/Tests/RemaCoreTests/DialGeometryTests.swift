import Testing
@testable import RemaCore

struct DialGeometryTests {
    let dial = DialGeometry()

    @Test func anglesFollowTwentyFourHours() {
        #expect(dial.angle(hour: 0, minute: 0) == 0)
        #expect(dial.angle(hour: 6, minute: 0) == 90)
        #expect(dial.angle(hour: 9, minute: 0) == 135)
        #expect(dial.angle(hour: 14, minute: 30) == 217.5)
    }

    @Test func markersLandWhereTheMockupHasThem() {
        let expected: [(Int, Int, Double, Double)] = [
            (14, 30, 59.03, 245.52),
            (9, 0, 234.05, 234.05),
            (19, 0, 11.53, 105.58),
            (21, 30, 59.03, 34.48),
        ]
        for (hour, minute, x, y) in expected {
            let point = dial.point(angle: dial.angle(hour: hour, minute: minute), radius: 133)
            #expect(abs(point.x - x) < 0.01)
            #expect(abs(point.y - y) < 0.01)
        }
    }

    @Test func handMatchesTheMockup() {
        let angle = dial.angle(hour: 13, minute: 50)
        let tip = dial.point(angle: angle, radius: 104)
        let tail = dial.point(angle: angle + 180, radius: 18)
        #expect(abs(tip.x - 91.98) < 0.01)
        #expect(abs(tip.y - 232.25) < 0.01)
        #expect(abs(tail.x - 148.31) < 0.01)
        #expect(abs(tail.y - 124.03) < 0.01)
    }

    @Test func numeralsSitOnTheInnerRing() {
        let three = dial.point(angle: 45, radius: 90)
        #expect(abs(three.x - 203.64) < 0.01)
        #expect(abs(three.y - 76.36) < 0.01)
    }
}
