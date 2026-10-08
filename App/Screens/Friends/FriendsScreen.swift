import RemaCore
import SwiftUI

struct FriendsScreen: View {
    let store: Store
    let onFriend: (String) -> Void
    let onInvite: () -> Void
    let onCode: (String) -> Void
    let onSignIn: () -> Void
    let onBack: () -> Void

    @State private var service = SharedService.shared
    @State private var account = Account.shared
    @State private var myName = SharedService.shared.myName
    @State private var code = ""
    @State private var enteringCode = false
    @FocusState private var nameFocused: Bool
    @FocusState private var codeFocused: Bool

    private var openInvites: [SharedService.SentInvite] {
        service.state.invites.filter { $0.state == "open" && $0.expires > Date() }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if account.isSignedIn {
                        content
                    } else {
                        Note("Sign in to share reminders with friends. Shared reminders live in the account.")
                            .padding(.top, 14)
                        Button("Sign in", action: onSignIn)
                            .buttonStyle(SmallButtonStyle(prominent: true))
                            .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .pinnedHeader {
                ScreenHeader(title: "Friends", leading: .back, action: onBack)
            }
            if account.isSignedIn, service.state.friends.count < 40 {
                PrimaryBar(action: onInvite) {
                    Text("Invite a friend")
                }
            }
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: service.state.friends)
        .animation(Motion.standard, value: openInvites)
        .task {
            await service.refresh()
            if !nameFocused {
                myName = service.myName
            }
        }
        .onDisappear {
            let typed = myName.trimmingCharacters(in: .whitespacesAndNewlines)
            if account.isSignedIn, typed != service.myName {
                Task { try? await service.setMyName(typed) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        Note("Friends see only the reminders you share with them. You choose each one's name yourself, they don't see it.")
            .padding(.top, 14)
        SectionLabel(text: "Your name for friends")
            .padding(.horizontal, 4)
            .padding(.top, 20)
            .padding(.bottom, 8)
        field(text: $myName, prompt: "How friends see you", focused: $nameFocused) {
            Task { try? await service.setMyName(myName) }
        }
        SectionLabel(verbatim: String(localized: "\(service.state.friends.count) of 40", bundle: .app, locale: .app))
            .padding(.horizontal, 4)
            .padding(.top, 20)
            .padding(.bottom, 8)
        if service.state.friends.isEmpty && openInvites.isEmpty {
            Text("No friends yet")
                .font(.app(.golos, 16, weight: 600))
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .panel()
        } else {
            PanelList {
                ForEach(Array(service.friends.enumerated()), id: \.element.id) { index, friend in
                    let name = service.name(of: friend.id, fallback: friend.name)
                    Button {
                        onFriend(friend.id)
                    } label: {
                        FriendRow(name: name, seed: friend.id, info: String(localized: "\(service.sharedCount(with: friend.id, in: store.reminders)) shared reminders", bundle: .app, locale: .app)) {
                            Glyph(paths: Icons.chevron, size: 16, lineWidth: 2, color: Palette.secondary)
                        }
                    }
                    .buttonStyle(RowPressStyle())
                    if index < service.state.friends.count - 1 || !openInvites.isEmpty {
                        Hairline()
                    }
                }
                ForEach(Array(openInvites.enumerated()), id: \.element.id) { index, invite in
                    let name = service.pendingName(invite.code) ?? String(localized: "Invitation", bundle: .app, locale: .app)
                    FriendRow(name: name, seed: invite.code, info: String(localized: "waiting for an answer to the invitation", bundle: .app, locale: .app)) {
                        Button {
                            Feedback.play(.select)
                            Task { await service.revoke(invite.code) }
                        } label: {
                            Text("Withdraw")
                                .font(.app(.golos, 13, weight: 600))
                                .foregroundStyle(Palette.accentText)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(RowPressStyle())
                    }
                    if index < openInvites.count - 1 {
                        Hairline()
                    }
                }
            }
        }
        if enteringCode {
            SectionLabel(text: "Invitation code")
                .padding(.horizontal, 4)
                .padding(.top, 20)
                .padding(.bottom, 8)
            field(text: $code, prompt: "8 letters and digits", focused: $codeFocused) {
                openCode()
            }
            .textInputAutocapitalization(.characters)
            .onAppear { codeFocused = true }
        } else {
            Button {
                withAnimation(Motion.standard) { enteringCode = true }
            } label: {
                Text("I have an invitation code")
                    .font(.app(.golos, 15, weight: 600))
                    .foregroundStyle(Palette.accentText)
                    .frame(height: 44)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(RowPressStyle())
            .padding(.top, 10)
        }
    }

    private func openCode() {
        // A pasted link works as well as the code itself.
        let cleaned = code.uppercased().components(separatedBy: "/").last?.filter { $0.isLetter || $0.isNumber } ?? ""
        guard cleaned.count == 8 else {
            Feedback.play(.error)
            return
        }
        code = ""
        enteringCode = false
        onCode(cleaned)
    }

    private func field(text: Binding<String>, prompt: LocalizedStringKey, focused: FocusState<Bool>.Binding, onSubmit: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .circular)
        return TextField(text: text, prompt: Text(prompt).foregroundColor(Palette.secondary)) {
            Text(prompt)
        }
        .font(.app(.golos, 17))
        .tint(Palette.accent)
        .focused(focused)
        .submitLabel(.done)
        .autocorrectionDisabled()
        .onSubmit(onSubmit)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background {
            shape
                .fill(Palette.well)
                .insetShadow(shape, Palette.wellShadow, blur: 3, y: 1)
        }
        .overlay(shape.strokeBorder(Palette.wellBorder, lineWidth: 1))
    }
}
