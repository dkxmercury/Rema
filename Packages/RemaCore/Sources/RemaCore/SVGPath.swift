import Foundation

public struct SVGPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

public enum SVGSegment: Equatable, Sendable {
    case move(SVGPoint)
    case line(SVGPoint)
    case cubic(SVGPoint, SVGPoint, SVGPoint)
    case quad(SVGPoint, SVGPoint)
    case close
}

public enum SVGPath {
    public static func parse(_ data: String) -> [SVGSegment] {
        var scanner = PathScanner(data)
        var out: [SVGSegment] = []
        var current = SVGPoint(0, 0)
        var subpathStart = SVGPoint(0, 0)
        var cubicControl: SVGPoint?
        var quadControl: SVGPoint?

        while let command = scanner.command() {
            let relative = command.isLowercase
            let kind = Character(command.uppercased())
            var first = true
            repeat {
                func point(_ x: Double, _ y: Double) -> SVGPoint {
                    relative ? SVGPoint(current.x + x, current.y + y) : SVGPoint(x, y)
                }
                switch kind {
                case "M":
                    guard let x = scanner.number(), let y = scanner.number() else { return out }
                    let target = point(x, y)
                    if first {
                        out.append(.move(target))
                        subpathStart = target
                    } else {
                        out.append(.line(target))
                    }
                    current = target
                    cubicControl = nil
                    quadControl = nil
                case "L":
                    guard let x = scanner.number(), let y = scanner.number() else { return out }
                    current = point(x, y)
                    out.append(.line(current))
                    cubicControl = nil
                    quadControl = nil
                case "H":
                    guard let x = scanner.number() else { return out }
                    current = SVGPoint(relative ? current.x + x : x, current.y)
                    out.append(.line(current))
                    cubicControl = nil
                    quadControl = nil
                case "V":
                    guard let y = scanner.number() else { return out }
                    current = SVGPoint(current.x, relative ? current.y + y : y)
                    out.append(.line(current))
                    cubicControl = nil
                    quadControl = nil
                case "C":
                    guard let x1 = scanner.number(), let y1 = scanner.number(),
                          let x2 = scanner.number(), let y2 = scanner.number(),
                          let x = scanner.number(), let y = scanner.number() else { return out }
                    let control1 = point(x1, y1)
                    let control2 = point(x2, y2)
                    let target = point(x, y)
                    out.append(.cubic(control1, control2, target))
                    current = target
                    cubicControl = control2
                    quadControl = nil
                case "S":
                    guard let x2 = scanner.number(), let y2 = scanner.number(),
                          let x = scanner.number(), let y = scanner.number() else { return out }
                    let control1 = cubicControl.map { SVGPoint(2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current
                    let control2 = point(x2, y2)
                    let target = point(x, y)
                    out.append(.cubic(control1, control2, target))
                    current = target
                    cubicControl = control2
                    quadControl = nil
                case "Q":
                    guard let x1 = scanner.number(), let y1 = scanner.number(),
                          let x = scanner.number(), let y = scanner.number() else { return out }
                    let control = point(x1, y1)
                    let target = point(x, y)
                    out.append(.quad(control, target))
                    current = target
                    quadControl = control
                    cubicControl = nil
                case "T":
                    guard let x = scanner.number(), let y = scanner.number() else { return out }
                    let control = quadControl.map { SVGPoint(2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current
                    let target = point(x, y)
                    out.append(.quad(control, target))
                    current = target
                    quadControl = control
                    cubicControl = nil
                case "A":
                    guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
                          let largeArc = scanner.flag(), let sweep = scanner.flag(),
                          let x = scanner.number(), let y = scanner.number() else { return out }
                    let target = point(x, y)
                    out.append(contentsOf: arc(from: current, to: target, rx: rx, ry: ry, rotation: rotation, largeArc: largeArc, sweep: sweep))
                    current = target
                    cubicControl = nil
                    quadControl = nil
                case "Z":
                    out.append(.close)
                    current = subpathStart
                    cubicControl = nil
                    quadControl = nil
                default:
                    return out
                }
                first = false
            } while kind != "Z" && scanner.hasNumber()
        }
        return out
    }

    static func arc(from start: SVGPoint, to end: SVGPoint, rx rxIn: Double, ry ryIn: Double, rotation: Double, largeArc: Bool, sweep: Bool) -> [SVGSegment] {
        if start == end {
            return []
        }
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        if rx == 0 || ry == 0 {
            return [.line(end)]
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = denominator == 0 ? 0 : max(0, numerator / denominator).squareRoot()
        if largeArc == sweep {
            factor = -factor
        }
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }

        let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 {
            delta -= 2 * .pi
        } else if sweep && delta < 0 {
            delta += 2 * .pi
        }

        let count = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / Double(count)
        let handle = 4.0 / 3.0 * tan(step / 4)

        func place(_ ux: Double, _ uy: Double) -> SVGPoint {
            let x = ux * rx
            let y = uy * ry
            return SVGPoint(cosPhi * x - sinPhi * y + cx, sinPhi * x + cosPhi * y + cy)
        }

        var out: [SVGSegment] = []
        var from = theta
        for index in 0..<count {
            let to = from + step
            let control1 = place(cos(from) - handle * sin(from), sin(from) + handle * cos(from))
            let control2 = place(cos(to) + handle * sin(to), sin(to) - handle * cos(to))
            let target = index == count - 1 ? end : place(cos(to), sin(to))
            out.append(.cubic(control1, control2, target))
            from = to
        }
        return out
    }
}

struct PathScanner {
    private let characters: [Character]
    private var index = 0

    init(_ text: String) {
        characters = Array(text)
    }

    private static func isDigit(_ character: Character) -> Bool {
        ("0"..."9").contains(character)
    }

    private mutating func skipSeparators() {
        while index < characters.count, characters[index].isWhitespace || characters[index] == "," {
            index += 1
        }
    }

    mutating func command() -> Character? {
        skipSeparators()
        guard index < characters.count else { return nil }
        let character = characters[index]
        guard character.isLetter, character != "e", character != "E" else { return nil }
        index += 1
        return character
    }

    mutating func hasNumber() -> Bool {
        skipSeparators()
        guard index < characters.count else { return false }
        let character = characters[index]
        return Self.isDigit(character) || character == "-" || character == "+" || character == "."
    }

    mutating func number() -> Double? {
        skipSeparators()
        var text = ""
        if index < characters.count, characters[index] == "-" || characters[index] == "+" {
            text.append(characters[index])
            index += 1
        }
        var seenDot = false
        var seenDigit = false
        while index < characters.count {
            let character = characters[index]
            if Self.isDigit(character) {
                text.append(character)
                seenDigit = true
                index += 1
            } else if character == ".", !seenDot {
                text.append(character)
                seenDot = true
                index += 1
            } else {
                break
            }
        }
        if seenDigit, index < characters.count, characters[index] == "e" || characters[index] == "E" {
            var lookahead = index + 1
            var exponent = "e"
            if lookahead < characters.count, characters[lookahead] == "-" || characters[lookahead] == "+" {
                exponent.append(characters[lookahead])
                lookahead += 1
            }
            var exponentDigits = false
            while lookahead < characters.count, Self.isDigit(characters[lookahead]) {
                exponent.append(characters[lookahead])
                lookahead += 1
                exponentDigits = true
            }
            if exponentDigits {
                text += exponent
                index = lookahead
            }
        }
        return seenDigit ? Double(text) : nil
    }

    mutating func flag() -> Bool? {
        skipSeparators()
        guard index < characters.count, characters[index] == "0" || characters[index] == "1" else { return nil }
        let value = characters[index] == "1"
        index += 1
        return value
    }
}
