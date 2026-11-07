import Foundation

public struct DialGeometry: Sendable {
    public let size: Double

    public init(size: Double = 280) {
        self.size = size
    }

    public var center: Double {
        size / 2
    }

    // A real clock: the short hand goes round in twelve hours, so 9:00 and 21:00 share a place.
    public func clockAngle(hour: Int, minute: Int) -> Double {
        (Double(hour % 12) + Double(minute) / 60) / 12 * 360
    }

    public func clockAngle(minutes: Double) -> Double {
        minutes.truncatingRemainder(dividingBy: 720) / 720 * 360
    }

    public func minuteAngle(minutes: Double) -> Double {
        minutes.truncatingRemainder(dividingBy: 60) / 60 * 360
    }

    public func point(angle degrees: Double, radius: Double) -> SVGPoint {
        let radians = degrees * .pi / 180
        return SVGPoint(center + radius * sin(radians), center - radius * cos(radians))
    }
}
