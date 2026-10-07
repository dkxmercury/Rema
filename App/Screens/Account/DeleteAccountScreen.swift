import SwiftUI

struct DeleteAccountScreen: View {
    var onDeleted: () -> Void
    var onBack: () -> Void

    private enum Step: Equatable {
        case warning
        case code(String)
        case confirm
    }

    private enum Field: Hashable {
        case code
    }

    @State private var step = Step.warning
    @State private var code = ""
    @State private var busy = false
    @State private var problem: String?
    @State private var sentAt: Date?
    @FocusState private var focus: Field?

    // Apple's relay takes mail only from registered senders, so a hidden address gets no code.
    private var codeByMail: Bool {
        let email = Account.shared.visibleEmail.lowercased()
        return !email.isEmpty && !email.hasSuffix("@privaterelay.appleid.com")
    }

    private var canSubmit: Bool {
        switch step {
        case .warning, .confirm: true
        case .code: code.count == 6
        }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Everything will be deleted")
                            .font(.app(.golos, 17, weight: 600))
                            .foregroundStyle(Palette.urgentText)
                        Text("Your account will be deleted together with all reminders, places, your own sounds and settings. They disappear from the server and from this phone. This cannot be undone.")
                            .font(.app(.golos, 15))
                            .lineHeight(21, .golos, 15)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
                    .padding(.top, 14)
                    switch step {
                    case .warning:
                        EmptyView()
                    case .confirm:
                        FormNote(text: "This account has no email we can send a code to, so it is deleted right after you confirm.")
                            .padding(.top, 16)
                    case .code(let email):
                        FormNote(text: "We sent a 6-digit code to \(email). It works for 15 minutes.")
                            .padding(.top, 16)
                        AuthField(title: "Code from the email", text: $code, kind: .code, focus: $focus, field: Field.code, submit: submit)
                            .padding(.top, 16)
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            let ready = sentAt.map { timeline.date.timeIntervalSince($0) >= 60 } ?? true
                            Button(action: requestCode) {
                                Text("Send the code again")
                                    .font(.app(.golos, 15, weight: 600))
                                    .foregroundStyle(ready ? Palette.accentTextOnBackground : Palette.faint)
                                    .padding(.horizontal, 4)
                                    .frame(height: 44)
                            }
                            .buttonStyle(RowPressStyle())
                            .disabled(!ready || busy)
                        }
                        .padding(.top, 6)
                    }
                    if let problem {
                        FormProblem(text: problem)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
                .animation(Motion.standard, value: step)
                .animation(Motion.standard, value: problem)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "Delete account", leading: .back, action: onBack)
            }
            PrimaryBar(action: submit) {
                if busy {
                    ProgressView().tint(Palette.onAccent)
                } else if step == .warning {
                    if codeByMail {
                        Text("Send a code to the email")
                    } else {
                        Text("Continue")
                    }
                } else {
                    Text("Delete forever")
                }
            }
            .disabled(!canSubmit || busy)
        }
        .foregroundStyle(Palette.text)
        .onChange(of: code) { _, value in
            let digits = String(value.filter(\.isNumber).prefix(6))
            if digits != value {
                code = digits
            } else if digits.count == 6 {
                // The number pad has no return key, and the button waits under the keyboard.
                focus = nil
            }
        }
    }

    private func submit() {
        guard canSubmit, !busy else { return }
        if step == .warning {
            requestCode()
        } else {
            delete()
        }
    }

    private func requestCode() {
        guard !busy else { return }
        busy = true
        problem = nil
        Task {
            defer { busy = false }
            do {
                switch try await Account.shared.requestDeletionCode() {
                case .email(let email):
                    sentAt = Date()
                    code = ""
                    step = .code(email)
                    focus = .code
                case .none:
                    step = .confirm
                }
            } catch Backend.Failure.invalid(let reason) where reason == "code_limit" {
                problem = String(localized: "You asked for too many codes today. Try again tomorrow.", bundle: .app, locale: .app)
            } catch Backend.Failure.unauthorized {
                problem = String(localized: "The sign-in has expired. Sign in again.", bundle: .app, locale: .app)
            } catch let failure as Backend.Failure {
                problem = failure.message
            } catch {
                problem = String(localized: "Something went wrong. Try again.", bundle: .app, locale: .app)
            }
        }
    }

    private func delete() {
        guard !busy else { return }
        focus = nil
        busy = true
        problem = nil
        Task {
            defer { busy = false }
            do {
                try await SyncService.shared.deleteAccount(code: code)
                Feedback.play(.save)
                onDeleted()
            } catch Backend.Failure.invalid(let reason) where reason == "wrong_code" {
                problem = String(localized: "The code is wrong. Check the email and try again.", bundle: .app, locale: .app)
            } catch Backend.Failure.invalid(let reason) where reason == "expired_code" {
                problem = String(localized: "The code has expired. Send a new one.", bundle: .app, locale: .app)
                sentAt = nil
            } catch Backend.Failure.unauthorized {
                problem = String(localized: "The sign-in has expired. Sign in again.", bundle: .app, locale: .app)
            } catch let failure as Backend.Failure {
                problem = failure == .offline || failure == .rateLimited ? failure.message : String(localized: "Could not delete the account. Try again.", bundle: .app, locale: .app)
            } catch {
                problem = String(localized: "Could not delete the account. Try again.", bundle: .app, locale: .app)
            }
        }
    }
}
