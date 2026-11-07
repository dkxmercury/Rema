import Testing
@testable import RemaCore

struct DialGeometryTests {
    let dial = DialGeometry()

    @Test func clockAnglesFollowTwelveHours() {
        #expect(dial.clockAngle(hour: 0, minute: 0) == 0)
        #expect(dial.clockAngle(hour: 12, minute: 0) == 0)
        #expect(dial.clockAngle(hour: 9, minute: 0) == 270)
        #expect(dial.clockAngle(hour: 21, minute: 0) == 270)
        #expect(dial.clockAngle(hour: 14, minute: 30) == 75)
        #expect(dial.clockAngle(minutes: 13 * 60 + 50) == 55)
        #expect(dial.minuteAngle(minutes: 13 * 60 + 50) == 300)
    }

    @Test func markersLandWhereTheMockupHasThem() {
        let expected: [(Int, Int, Double, Double)] = [
            (14, 30, 268.47, 105.58),
            (19, 0, 73.5, 255.18),
            (21, 30, 11.53, 105.58),
            (1, 0, 206.5, 24.82),
        ]
        for (hour, minute, x, y) in expected {
            let point = dial.point(angle: dial.clockAngle(hour: hour, minute: minute), radius: 133)
            #expect(abs(point.x - x) < 0.01)
            #expect(abs(point.y - y) < 0.01)
        }
    }

    @Test func handsMatchTheMockup() {
        let now = Double(13 * 60 + 50)
        let hour = dial.point(angle: dial.clockAngle(minutes: now), radius: 58)
        let minute = dial.point(angle: dial.minuteAngle(minutes: now), radius: 96)
        #expect(abs(hour.x - 187.51) < 0.01)
        #expect(abs(hour.y - 106.73) < 0.01)
        #expect(abs(minute.x - 56.86) < 0.01)
        #expect(abs(minute.y - 92) < 0.01)
    }

    @Test func numeralsSitOnTheInnerRing() {
        let three = dial.point(angle: 90, radius: 88)
        #expect(abs(three.x - 228) < 0.01)
        #expect(abs(three.y - 140) < 0.01)
    }
}
