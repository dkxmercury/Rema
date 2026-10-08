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

// The first visit of the friends screen tells in three steps how sharing works.
struct FriendsTour: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Glyph(paths: Icons.people, size: 34, lineWidth: 1.8, color: Palette.accentText)
                    .padding(.top, 34)
                Text("How shared reminders work")
                    .font(.app(.golos, 24, weight: 600))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                VStack(alignment: .leading, spacing: 18) {
                    step(1, "Invite a friend with a link or a QR code. Rema does not look people up by email or phone number.")
                    step(2, "Make a reminder and tap “With friends”. The friend gets an invitation and decides.")
                    step(3, "Everybody gets it at the same moment. Each ticks it alone, or one “done” counts for everybody.")
                }
                .padding(.top, 22)
                Spacer(minLength: 16)
                Button(action: onDone) {
                    Text("Got it")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .foregroundStyle(Palette.text)
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(verbatim: "\(number)")
                .font(.app(.jost, 17, weight: 600))
                .foregroundStyle(Palette.onAccent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Palette.accent))
                .accessibilityHidden(true)
            Text(text)
                .font(.app(.golos, 16))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Friends the one who made a reminder can still add to it.
struct MemberPicker: View {
    let candidates: [SharedPerson]
    let onAdd: ([SharedPerson]) -> Void
    let onClose: () -> Void

    @State private var chosen: Set<String> = []

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Add friends")
                        .font(.app(.golos, 22, weight: 600))
                    Spacer()
                    RoundIconButton(icon: Icons.close, label: "Close", action: onClose)
                        .frame(width: 40, height: 40)
                }
                .padding(.top, 18)
                if candidates.isEmpty {
                    Note("Everybody you can invite is already here.")
                        .padding(.top, 14)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(candidates, id: \.id) { person in
                            Chip(title: "\(person.name)", selected: chosen.contains(person.id)) {
                                Feedback.play(chosen.contains(person.id) ? .uncheck : .check)
                                if chosen.contains(person.id) {
                                    chosen.remove(person.id)
                                } else {
                                    chosen.insert(person.id)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                }
                Spacer(minLength: 16)
                Button {
                    onAdd(candidates.filter { chosen.contains($0.id) })
                } label: {
                    Text("Add")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(chosen.isEmpty)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .foregroundStyle(Palette.text)
    }
}

extension Backend.Failure {
    // The texts of `message` are written for the sign-in form and say the wrong thing here.
    var friendsMessage: String {
        switch self {
        case .offline:
            return message
        case .unauthorized:
            return String(localized: "The sign-in has expired. Sign in again.", bundle: .app, locale: .app)
        case .rateLimited:
            return String(localized: "Too many attempts. Try again later.", bundle: .app, locale: .app)
        case .conflict(let code) where code == "friend_limit":
            return String(localized: "There are already 40 friends.", bundle: .app, locale: .app)
        case .conflict:
            return String(localized: "Too many requests, try again tomorrow.", bundle: .app, locale: .app)
        case .invalid(let code) where code == "not_found":
            return String(localized: "This person or reminder is no longer here.", bundle: .app, locale: .app)
        case .invalid(let code) where code == "unverified":
            return String(localized: "Confirm your email first. Open the link in the email from Rema.", bundle: .app, locale: .app)
        default:
            return String(localized: "Something went wrong. Try again.", bundle: .app, locale: .app)
        }
    }
}

// Friends wait for a confirmed email; the letter with the link can be sent again from here.
struct ConfirmEmailNote: View {
    var centered = false

    @State private var sent = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 10) {
            Note(verbatim: Backend.Failure.invalid("unverified").friendsMessage)
            if sent {
                Note("If it is not in your inbox, look in spam. You can send it again in a minute.")
            } else {
                Button("Send the email again") {
                    Task {
                        do {
                            try await Account.shared.resendConfirmation()
                            withAnimation(Motion.standard) { sent = true }
                        } catch {
                            failed = true
                        }
                    }
                }
                .buttonStyle(SmallButtonStyle(prominent: false))
            }
            if failed, !sent {
                Note("Could not send the email. Try again.")
            }
        }
        .multilineTextAlignment(centered ? .center : .leading)
    }
}

extension Backend.Failure {
    var needsConfirmedEmail: Bool {
        self == .invalid("unverified")
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
