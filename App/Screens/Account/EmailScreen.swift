import SwiftUI

struct EmailScreen: View {
    enum Mode: Hashable {
        case signIn
        case signUp
    }

    enum Field: Hashable {
        case email
        case password
    }

    var onReset: (String) -> Void
    var onSignedIn: () -> Void
    var onBack: () -> Void

    @State private var mode: Mode
    @State private var email: String
    @State private var password: String
    @State private var busy = false
    @State private var problem: String?
    @FocusState private var focus: Field?

    init(mode: Mode = .signIn, email: String = "", password: String = "", onReset: @escaping (String) -> Void, onSignedIn: @escaping () -> Void, onBack: @escaping () -> Void) {
        _mode = State(initialValue: mode)
        _email = State(initialValue: email)
        _password = State(initialValue: password)
        self.onReset = onReset
        self.onSignedIn = onSignedIn
        self.onBack = onBack
    }

    private var longEnough: Bool {
        password.count >= 8
    }

    private var canSubmit: Bool {
        email.looksLikeEmail && (mode == .signIn ? !password.isEmpty : longEnough)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Segmented(options: [(Mode.signIn, "Sign in tab"), (Mode.signUp, "Sign up tab")], selection: $mode)
                        .padding(.top, 14)
                    AuthField(title: "Email", text: $email, kind: .email, focus: $focus, field: Field.email) {
                        focus = .password
                    }
                    .padding(.top, 22)
                    AuthField(title: "Password", text: $password, kind: mode == .signUp ? .newPassword : .password, focus: $focus, field: Field.password, submit: submit)
                        .padding(.top, 16)
                    if mode == .signIn {
                        Button {
                            onReset(email)
                        } label: {
                            Text("Forgot password?")
                                .font(.app(.golos, 15, weight: 600))
                                .foregroundStyle(Palette.accentTextOnBackground)
                                .padding(.horizontal, 4)
                                .frame(height: 44)
                        }
                        .buttonStyle(RowPressStyle())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 6)
                    } else {
                        HStack(spacing: 6) {
                            Glyph(paths: Icons.check, size: 14, lineWidth: 2.6, color: longEnough ? Palette.granted : Palette.secondary)
                            Text("At least 8 characters")
                                .font(.app(.golos, 13))
                                .foregroundStyle(longEnough ? Palette.granted : Palette.secondary)
                        }
                        .padding(.top, 8)
                        .animation(Motion.small, value: longEnough)
                        FormNote(text: "Reminders already on this phone will move to the new account.")
                            .padding(.top, 22)
                    }
                    if let problem {
                        FormProblem(text: problem)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
                .animation(Motion.standard, value: mode)
                .animation(Motion.standard, value: problem)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "Email and password", leading: .back, action: onBack)
            }
            PrimaryBar(action: submit) {
                if busy {
                    ProgressView().tint(Palette.onAccent)
                } else {
                    Text(mode == .signIn ? LocalizedStringKey("Sign in") : LocalizedStringKey("Create account"))
                }
            }
            .disabled(!canSubmit || busy)
        }
        .foregroundStyle(Palette.text)
        .onChange(of: mode) { _, _ in problem = nil }
    }

    private func submit() {
        guard canSubmit, !busy else { return }
        focus = nil
        busy = true
        problem = nil
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        Task {
            defer { busy = false }
            do {
                if mode == .signIn {
                    try await Account.shared.signIn(email: address, password: password)
                } else {
                    try await Account.shared.signUp(email: address, password: password)
                }
                Feedback.play(.save)
                onSignedIn()
            } catch let failure as Backend.Failure {
                problem = failure.message
            } catch {
                problem = String(localized: "Something went wrong. Try again.")
            }
        }
    }
}
