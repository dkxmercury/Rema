import BackgroundTasks
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static let refreshTask = "uz.dkx.rema.refresh"

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AppLanguage.activate()
        AppFonts.register()
        SoundLibrary.prepare()
        Notifier.shared.configure()
        WatchLink.shared.activate()
        Store.shared.onChange = {
            Notifier.shared.scheduleSoon()
            Task { @MainActor in WatchLink.shared.send(store: Store.shared) }
        }
        Store.shared.onEdit = {
            Task { @MainActor in SyncService.shared.schedule() }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTask, using: nil) { task in
            Self.handleRefresh(task)
        }
        return true
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTask)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleRefresh(_ task: BGTask) {
        scheduleRefresh()
        let work = Task { @MainActor in
            await Remote.shared.refresh()
            if Remote.shared.isOn(.sync) {
                await SyncService.shared.run()
            }
            await Notifier.shared.reschedule()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }
}

@main
struct RemaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LocalizedRoot {
                RootView()
            }
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
                Task {
                    await Remote.shared.refresh()
                    await Account.shared.refreshIfNeeded()
                    if Remote.shared.isOn(.sync) {
                        SyncService.shared.becameActive()
                    }
                }
            case .background:
                LiveActivities.refresh(store: Store.shared)
                SyncService.shared.movedToBackground()
                AppDelegate.scheduleRefresh()
            default:
                break
            }
        }
    }
}
