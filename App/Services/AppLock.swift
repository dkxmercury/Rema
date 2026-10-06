import LocalAuthentication
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppLock {
    static let shared = AppLock()

    private static let enabledKey = "lock.enabled"
    private static let delayKey = "lock.delay"

    private(set) var enabled: Bool
    private(set) var delay: Int
    private(set) var locked = false
    private var leftAt: Date?
    private var window: UIWindow?
    private var asking = false

    private init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        delay = UserDefaults.standard.object(forKey: Self.delayKey) as? Int ?? 60
        locked = enabled
    }

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Face ID"
        }
    }

    var available: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func setEnabled(_ on: Bool) async {
        guard on != enabled else { return }
        if on {
            guard await authenticate() else { return }
        }
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
    }

    func setDelay(_ seconds: Int) {
        delay = seconds
        UserDefaults.standard.set(seconds, forKey: Self.delayKey)
    }

    func movedToBackground() {
        leftAt = Date()
    }

    func becameActive() {
        if enabled, !locked, let leftAt, Date().timeIntervalSince(leftAt) >= Double(delay) {
            locked = true
        }
        leftAt = nil
        guard locked else {
            hide()
            return
        }
        show()
        Task { await unlock() }
    }

    func unlock() async {
        guard locked, !asking else { return }
        asking = true
        let passed = await authenticate()
        asking = false
        if passed {
            locked = false
            hide()
        }
    }

    private func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Unlock Rema"))) ?? false
    }

    // A window of its own covers sheets and full screen covers too, which an overlay in the root view would not.
    private func show() {
        guard window == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let language = AppLanguage.current
        let screen = LockScreen()
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.layoutDirection)
        window.rootViewController = UIHostingController(rootView: screen)
        window.makeKeyAndVisible()
        self.window = window
    }

    private func hide() {
        window?.isHidden = true
        window = nil
    }
}

struct LockScreen: View {
    @State private var lock = AppLock.shared

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .circular)
                        .fill(cssGradient(160, [Palette.dialBezelTop, Palette.dialBezelBottom]).shadow(.drop(color: Palette.dialShadowNear, radius: 2, y: 2)).shadow(.drop(color: Palette.dialShadowFar, radius: 14, y: 12)))
                        .insetShadow(RoundedRectangle(cornerRadius: 24, style: .circular), Palette.dialBezelHighlight, y: 1)
                    MiniDial(hour: 10, minute: 10, size: 86)
                }
                .frame(width: 104, height: 104)
                Text("Rema is locked")
                    .font(.app(.jost, 28, weight: 500))
                    .padding(.top, 28)
                Text("Open it with \(lock.biometryName). Reminders come as usual.")
                    .font(.app(.golos, 16))
                    .lineSpacing(4)
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                Button {
                    Task { await lock.unlock() }
                } label: {
                    HStack(spacing: 10) {
                        Glyph(paths: Icons.faceID, size: 22, lineWidth: 2, color: Palette.onAccent)
                        Text("Open")
                    }
                    .padding(.horizontal, 28)
                }
                .buttonStyle(PrimaryButtonStyle())
                .fixedSize()
                .padding(.top, 32)
            }
            .padding(.horizontal, 32)
        }
        .foregroundStyle(Palette.text)
    }
}
