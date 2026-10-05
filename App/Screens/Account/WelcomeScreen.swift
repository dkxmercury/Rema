import SwiftUI

struct WelcomeScreen: View {
    var onEmail: () -> Void
    var onLanguage: () -> Void
    var onSkip: () -> Void
    var onSignedIn: () -> Void

    @State private var busy: Account.Method?
    @State private var problem: String?
    @State private var hand: Double = 0
    @Environment(\.introAnimations) private var introAnimations
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let handTarget: Double = 13 * 60 + 50

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                languageButton
            }
            Dial(
                size: 208,
                handMinutes: introAnimations && !reduceMotion ? hand : Self.handTarget,
                markers: [
                    DialMarker(id: 0, hour: 9, minute: 0, kind: .done),
                    DialMarker(id: 1, hour: 14, minute: 30, kind: .next),
                    DialMarker(id: 2, hour: 19, minute: 0, kind: .upcoming),
                    DialMarker(id: 3, hour: 21, minute: 30, kind: .upcoming),
                ],
                windowTime: "Rema",
                windowCaption: "",
                windowFontSize: 19,
                windowTitleOnly: true
            )
            .padding(.top, 22)
            Text("I’ll remind you on time")
                .font(.app(.jost, 30, weight: 500))
                .lineHeight(36, .jost, 30, weight: 500)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
            Text("Sign in and your reminders will be on all your devices. You can change phones without losing anything.")
                .font(.app(.golos, 15))
                .lineHeight(21, .golos, 15)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 310)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Spacer(minLength: 16)
            VStack(spacing: 10) {
                if let problem {
                    FormProblem(text: problem)
                        .multilineTextAlignment(.center)
                }
                AppleSignInButton(busy: busy == .apple) {
                    signIn(.apple) { try await Account.shared.signInWithApple() }
                }
                GoogleSignInButton(busy: busy == .google) {
                    signIn(.google) { try await Account.shared.signInWithGoogle() }
                }
                Button(action: onEmail) {
                    HStack(spacing: 10) {
                        Glyph(paths: Icons.envelope, size: 20, lineWidth: 2, color: Palette.text)
                        Text("Email and password")
                    }
                }
                .buttonStyle(RaisedButtonStyle())
                Button(action: onSkip) {
                    Text("Continue without signing in")
                        .font(.app(.golos, 15, weight: 600))
                        .foregroundStyle(Palette.accentTextOnBackground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(RowPressStyle())
                Text(legal)
                    .font(.app(.golos, 12))
                    .lineHeight(16, .golos, 12)
                    .foregroundStyle(Palette.secondary)
                    .tint(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(busy != nil)
            .animation(Motion.standard, value: problem)
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .bottom)
        .foregroundStyle(Palette.text)
        .onAppear {
            withAnimation(Motion.hand) { hand = Self.handTarget }
        }
    }

    private var languageButton: some View {
        Button(action: onLanguage) {
            HStack(spacing: 8) {
                Glyph(paths: Icons.globe, size: 18, lineWidth: 1.9, color: Palette.text)
                Text(verbatim: AppLanguage.current.nativeName)
                    .font(.app(.golos, 15, weight: 500))
                Glyph(paths: Icons.chevronDown, size: 14, lineWidth: 2.2, color: Palette.secondary)
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(height: 44)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(colors: [Palette.raisedTop, Palette.raisedBottom], startPoint: .top, endPoint: .bottom)
                            .shadow(.drop(color: Palette.raisedShadowNear, radius: 1, x: 0, y: 1))
                            .shadow(.drop(color: Palette.raisedShadowFar, radius: 5, x: 0, y: 4))
                    )
                    .insetShadow(Capsule(), Palette.raisedHighlight, y: 1)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text("App language"))
        .accessibilityValue(Text(verbatim: AppLanguage.current.nativeName))
    }

    private var legal: AttributedString {
        var text = AttributedString(localized: "By continuing, you agree to the [Terms](https://remaapp.cc/terms/) and the [Privacy Policy](https://remaapp.cc/privacy/).")
        for run in text.runs where run.link != nil {
            text[run.range].underlineStyle = .single
        }
        return text
    }

    private func signIn(_ method: Account.Method, _ work: @escaping () async throws -> Void) {
        busy = method
        problem = nil
        Task {
            defer { busy = nil }
            do {
                try await work()
                Feedback.play(.save)
                onSignedIn()
            } catch is CancellationError {
            } catch let failure as Backend.Failure {
                problem = failure.message
            } catch GoogleAuthorization.Problem.notConfigured {
                problem = String(localized: "Signing in with Google is not available yet.")
            } catch {
                problem = String(localized: "Could not sign in. Try again.")
            }
        }
    }
}
