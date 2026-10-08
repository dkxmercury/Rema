import Foundation
import RemaCore

// The names I gave friends, kept where the lines of any list can read them, the share sheet included.
enum SharedNames {
    nonisolated(unsafe) static var names: [String: String] = [:]
    nonisolated(unsafe) static var me: String?

    static func name(of id: String, fallback: String) -> String {
        if let mine = names[id], !mine.isEmpty {
            return mine
        }
        return fallback.isEmpty ? String(localized: "Friend", bundle: .app, locale: .app) : fallback
    }

    // «Аня, сестра и Илья»: the others in the reminder.
    static func line(_ shared: SharedInfo) -> String {
        var result: [String] = []
        if !shared.isMine {
            result.append(name(of: shared.owner.id, fallback: shared.owner.name))
        }
        for member in shared.members where member.id != me && (member.status == SharedStatus.accepted || member.status == SharedStatus.invited) {
            result.append(name(of: member.id, fallback: member.name))
        }
        return result.formatted(.list(type: .and).locale(Locale.app))
    }
}
