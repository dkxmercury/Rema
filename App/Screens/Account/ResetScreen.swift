import SwiftUI

struct ResetScreen: View {
    var onBack: () -> Void

    @State private var email: String
    @State private var sentAt: Date?
    @State private var busy = false
    @State private var problem: String?
    @FocusState private var focus: Bool?

    init(email: String = "", sentAt: Date? = nil, onBack: @escaping () -> Void) {
        _email = State(initialValue: email)
        _sentAt = State(initialValue: sentAt)
        self.onBack = onBack
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("We will send an email with a link. Use it to set a new password.")
                        .font(.app(.golos, 15))
                        .lineHeight(21, .golos, 15)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.top, 18)
                    AuthField(title: "Email", text: $email, kind: .email, focus: $focus, field: true, submit: send)
                        .padding(.top, 20)
                    if sentAt != nil {
                        sentCard
                            .padding(.top, 18)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                    if let problem {
                        FormProblem(text: problem)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
                .animation(Motion.standard, value: sentAt)
                .animation(Motion.standard, value: problem)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "Password reset", leading: .back, action: onBack)
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let waiting = sentAt.map { timeline.date.timeIntervalSince($0) < 60 } ?? false
                PrimaryBar(action: send) {
                    if busy {
                        ProgressView().tint(Palette.onAccent)
                    } else {
                        Text("Send email")
                    }
                }
                .disabled(!email.looksLikeEmail || busy || waiting)
            }
        }
        .foregroundStyle(Palette.text)
    }

    private var sentCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Glyph(paths: Icons.check, size: 15, lineWidth: 3, color: .white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .circular).fill(Palette.yearly))
            VStack(alignment: .leading, spacing: 2) {
                Text("Email sent")
                    .font(.app(.golos, 15, weight: 600))
                Text("If it is not in your inbox, look in spam. You can send it again in a minute.")
                    .font(.app(.golos, 13))
                    .lineHeight(18, .golos, 13)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .panel(radius: 18)
    }

    private func send() {
        guard email.looksLikeEmail, !busy else { return }
        if let sentAt, Date().timeIntervalSince(sentAt) < 60 { return }
        focus = nil
        busy = true
        problem = nil
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        Task {
            defer { busy = false }
            do {
                try await Account.shared.requestReset(email: address)
                sentAt = Date()
                Feedback.play(.save)
            } catch let failure as Backend.Failure {
                problem = failure == .rateLimited ? failure.message : String(localized: "Could not send the email. Try again.", locale: .app)
            } catch {
                problem = String(localized: "Could not send the email. Try again.", locale: .app)
            }
        }
    }
}
