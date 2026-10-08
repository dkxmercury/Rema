import Foundation

// How many times in a row a reminder was put off; kept on this phone only.
enum SnoozeStats {
    private static let key = "snoozeStreaks"

    private static var table: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func add(_ id: UUID) {
        table[id.uuidString, default: 0] += 1
    }

    static func reset(_ id: UUID) {
        guard table[id.uuidString] != nil else { return }
        table[id.uuidString] = nil
    }

    static func count(_ id: UUID) -> Int {
        table[id.uuidString] ?? 0
    }
}
