import Foundation
import RemaCore

// The names I gave friends and the account they belong to, kept in the app group,
// so the widgets, the share sheet and the push extension read the same ones as the app.
enum SharedNames {
    private static let namesKey = "shared.names"
    private static let meKey = "shared.me"
    private static let defaults = UserDefaults(suiteName: SharedStore.appGroup)

    static var names: [String: String] {
        get { defaults?.dictionary(forKey: namesKey) as? [String: String] ?? [:] }
        set { defaults?.set(newValue, forKey: namesKey) }
    }

    static var me: String? {
        get { defaults?.string(forKey: meKey) }
        set { defaults?.set(newValue, forKey: meKey) }
    }

    static func name(of id: String, fallback: String, known: [String: String]? = nil) -> String {
        if let mine = (known ?? names)[id], !mine.isEmpty {
            return mine
        }
        return fallback.isEmpty ? String(localized: "Friend", bundle: .app, locale: .app) : fallback
    }

    // «Аня, сестра и Илья»: the others in the reminder.
    static func line(_ shared: SharedInfo) -> String {
        let known = names
        let account = me
        var result: [String] = []
        if !shared.isMine {
            result.append(name(of: shared.owner.id, fallback: shared.owner.name, known: known))
        }
        for member in shared.members where member.id != account && (member.status == SharedStatus.accepted || member.status == SharedStatus.invited) {
            result.append(name(of: member.id, fallback: member.name, known: known))
        }
        return result.formatted(.list(type: .and).locale(Locale.app))
    }
}
