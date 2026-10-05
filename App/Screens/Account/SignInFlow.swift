import SwiftUI

enum SignInRoute: Hashable {
    case email
    case reset(String)
}

struct SignInFlow: View {
    var onLanguage: () -> Void
    var onFinish: (_ signedIn: Bool) -> Void

    @State private var path: [SignInRoute] = []

    var body: some View {
        PushStack(path: $path) {
            WelcomeScreen(
                onEmail: { path.append(.email) },
                onLanguage: onLanguage,
                onSkip: { onFinish(false) },
                onSignedIn: { onFinish(true) }
            )
        } destination: { route in
            switch route {
            case .email:
                EmailScreen(onReset: { path.append(.reset($0)) }, onSignedIn: { onFinish(true) }, onBack: { path.removeLast() })
            case .reset(let email):
                ResetScreen(email: email, onBack: { path.removeLast() })
            }
        }
    }
}
