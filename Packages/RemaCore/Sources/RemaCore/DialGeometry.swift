import Foundation

public struct DialGeometry: Sendable {
    public let size: Double

    public init(size: Double = 280) {
        self.size = size
    }

    public var center: Double {
        size / 2
    }

    public func angle(hour: Int, minute: Int) -> Double {
        (Double(hour) + Double(minute) / 60) / 24 * 360
    }

    public func point(angle degrees: Double, radius: Double) -> SVGPoint {
        let radians = degrees * .pi / 180
        return SVGPoint(center + radius * sin(radians), center - radius * cos(radians))
    }
}
