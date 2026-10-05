import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AppFonts.register()
        SoundLibrary.prepare()
        Notifier.shared.configure()
        WatchLink.shared.activate()
        Store.shared.onChange = {
            Notifier.shared.scheduleSoon()
            Task { @MainActor in WatchLink.shared.send(store: Store.shared) }
        }
        return true
    }
}

@main
struct RemaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    Notifier.shared.scheduleSoon()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Store.shared.reloadIfChanged()
                Notifier.shared.scheduleSoon()
                LiveActivities.refresh(store: Store.shared)
            case .background:
                LiveActivities.refresh(store: Store.shared)
            default:
                break
            }
        }
    }
}
