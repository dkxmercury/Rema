import RemaCore
import SwiftUI

struct Avatar: View {
    let name: String
    let seed: String
    var size: CGFloat = 36

    private static let colors: [UInt32] = [0xF7924F, 0x7FA7E8, 0x9CCB8A, 0xE8A0C8, 0xD9C27A, 0xA9A1E0]

    // The same friend keeps the same colour on every screen.
    private var color: Color {
        let sum = seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hex: Self.colors[sum % Self.colors.count])
    }

    var body: some View {
        Text(verbatim: String(name.prefix(1)).uppercased())
            .font(.app(.golos, size * 0.42, weight: 600))
            .foregroundStyle(Color(hex: 0x1C1B19))
            .frame(width: size, height: size)
            .background(Circle().fill(color))
            .accessibilityHidden(true)
    }
}

struct Note: View {
    let text: Text

    init(_ key: LocalizedStringKey) {
        text = Text(key)
    }

    init(verbatim: String) {
        text = Text(verbatim: verbatim)
    }

    var body: some View {
        text
            .font(.app(.golos, 13))
            .foregroundStyle(Palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
    }
}

struct FriendRow<Trailing: View>: View {
    let name: String
    let seed: String
    let info: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: name, seed: seed)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(.app(.golos, 16, weight: 500))
                    .lineLimit(1)
                Text(verbatim: info)
                    .font(.app(.golos, 12))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}

struct ActionRow: View {
    let icon: [String]
    let title: Text
    var tint: Color = Palette.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Glyph(paths: icon, size: 20, lineWidth: 2, color: tint)
                title
                    .font(.app(.golos, 16, weight: 500))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}

extension SharedService {
    // How many shared reminders I have with this friend, either side made them.
    func sharedCount(with friendID: String, in reminders: [Reminder]) -> Int {
        reminders.filter { reminder in
            guard let shared = reminder.shared, reminder.deletedAt == nil else { return false }
            return shared.owner.id == friendID || shared.members.contains { $0.id == friendID && ($0.status == SharedStatus.accepted || $0.status == SharedStatus.invited) }
        }.count
    }

}
