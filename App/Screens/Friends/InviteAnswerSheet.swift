import RemaCore
import SwiftUI

struct InviteTarget: Identifiable {
    let code: String
    var id: String { code }
}

struct InviteAnswerSheet: View {
    let code: String
    let onSignIn: () -> Void
    let onClose: () -> Void

    @State private var service = SharedService.shared
    @State private var account = Account.shared
    @State private var invite: SharedService.InviteView?
    @State private var problem: String?
    @State private var busy = false
    @State private var friendsNow = false

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    RoundIconButton(icon: Icons.close, label: "Close", action: onClose)
                        .frame(width: 40, height: 40)
                }
                .padding(.top, 18)
                Spacer(minLength: 0)
                if !account.isSignedIn {
                    Glyph(paths: Icons.people, size: 40, lineWidth: 1.8, color: Palette.accentText)
                    Text("Sign in to accept the invitation")
                        .font(.app(.golos, 20, weight: 600))
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)
                    Button("Sign in") {
                        onClose()
                        onSignIn()
                    }
                    .buttonStyle(SmallButtonStyle(prominent: true))
                    .padding(.top, 16)
                } else if let invite, !invite.inviter.id.isEmpty {
                    Avatar(name: invite.inviter.name.isEmpty ? "?" : invite.inviter.name, seed: invite.inviter.id, size: 72)
                    Text(verbatim: headline(invite))
                        .font(.app(.golos, 20, weight: 600))
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)
                    if let problem {
                        Note(verbatim: problem)
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                    } else if !friendsNow {
                        Note("Friends see only the reminders you share with them.")
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                    }
                } else if let problem {
                    Note(verbatim: problem)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView()
                }
                Spacer(minLength: 0)
                if account.isSignedIn, let invite, invite.state == "open", !invite.own, !friendsNow, problem == nil {
                    Button(action: accept) {
                        Text("Accept")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy)
                    Button {
                        Task {
                            await service.decline(code)
                            onClose()
                        }
                    } label: {
                        Text("Decline")
                            .font(.app(.golos, 16, weight: 600))
                            .frame(height: 48)
                    }
                    .buttonStyle(RowPressStyle())
                    .padding(.top, 6)
                } else if friendsNow {
                    Button(action: onClose) {
                        Text("Done")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .foregroundStyle(Palette.text)
        .task { await load() }
    }

    private func headline(_ invite: SharedService.InviteView) -> String {
        let name = invite.inviter.name.isEmpty ? String(localized: "Someone", bundle: .app, locale: .app) : invite.inviter.name
        if friendsNow {
            return String(localized: "You and \(name) are friends now", bundle: .app, locale: .app)
        }
        return String(localized: "\(name) wants to be friends in Rema", bundle: .app, locale: .app)
    }

    private func load() async {
        guard account.isSignedIn, invite == nil else { return }
        do {
            let view = try await service.invite(code)
            invite = view
            if view.own {
                problem = String(localized: "This is your own invitation. Send the link to a friend.", bundle: .app, locale: .app)
            } else if view.state == "expired" {
                problem = String(localized: "This invitation has expired. Ask for a new one.", bundle: .app, locale: .app)
            } else if view.state != "open" {
                problem = String(localized: "This invitation can no longer be used.", bundle: .app, locale: .app)
            }
        } catch let failure as Backend.Failure {
            switch failure {
            case .offline, .rateLimited, .unauthorized:
                problem = failure.friendsMessage
            default:
                problem = String(localized: "This invitation does not exist.", bundle: .app, locale: .app)
            }
        } catch {
            problem = Backend.Failure.server.message
        }
    }

    private func accept() {
        busy = true
        Task {
            do {
                try await service.accept(code)
                Feedback.play(.save)
                withAnimation(Motion.standard) { friendsNow = true }
            } catch let failure as Backend.Failure {
                switch failure {
                case .conflict(let code) where code == "friend_limit":
                    problem = String(localized: "There are already 40 friends.", bundle: .app, locale: .app)
                case .offline, .rateLimited, .unauthorized:
                    problem = failure.friendsMessage
                default:
                    problem = String(localized: "This invitation can no longer be used.", bundle: .app, locale: .app)
                }
            } catch {
                problem = Backend.Failure.server.message
            }
            busy = false
        }
    }
}
