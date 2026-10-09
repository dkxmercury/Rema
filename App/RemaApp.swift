import BackgroundTasks
import CoreSpotlight
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static let refreshTask = "uz.dkx.rema.refresh"

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AppLanguage.activate()
        #if DEBUG
        MainActor.assumeIsolated { DemoMode.prepare() }
        #endif
        AppFonts.register()
        SoundLibrary.prepare()
        Notifier.shared.configure()
        WatchLink.shared.activate()
        Store.shared.onChange = {
            Notifier.shared.scheduleSoon()
            Task { @MainActor in
                WatchLink.shared.send(store: Store.shared)
                SpotlightIndex.scheduleUpdate()
            }
        }
        Store.shared.onEdit = {
            Task { @MainActor in SyncService.shared.schedule() }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTask, using: nil) { task in
            Self.handleRefresh(task)
        }
        Task { @MainActor in PushRegistration.shared.start() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushRegistration.shared.received(deviceToken) }
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTask)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleRefresh(_ task: BGTask) {
        scheduleRefresh()
        let finish = Completion(task)
        let work = Task { @MainActor in
            Store.shared.reloadIfChanged()
            await Remote.shared.refresh()
            if Remote.shared.isOn(.sync) {
                await Account.shared.refreshIfNeeded()
                await SyncService.shared.run()
            }
            await WeatherAdvisor.shared.refresh()
            await Notifier.shared.reschedule()
            WatchLink.shared.send(store: Store.shared)
            finish(true)
        }
        task.expirationHandler = {
            work.cancel()
            finish(false)
        }
    }
}

// The system wants exactly one answer per task, whichever comes first, the work or the deadline.
private final class Completion: @unchecked Sendable {
    private let task: BGTask
    private let lock = NSLock()
    private var done = false

    init(_ task: BGTask) {
        self.task = task
    }

    func callAsFunction(_ success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        task.setTaskCompleted(success: success)
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
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String, let id = UUID(uuidString: raw) else { return }
                RootNavigation.shared.openRequest = id
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                KeyboardDismissal.shared.installEverywhere()
                AppLock.shared.becameActive()
                Store.shared.reloadIfChanged()
                PushRegistration.shared.start()
                Notifier.shared.scheduleSoon()
                LiveActivities.refresh(store: Store.shared)
                WatchLink.shared.send(store: Store.shared)
                SyncService.shared.dropGuestTombstones()
                Task {
                    await NotificationAccess.shared.refresh()
                    await Remote.shared.refresh()
                    await WeatherAdvisor.shared.refresh()
                    await Account.shared.refreshIfNeeded()
                    if Remote.shared.isOn(.sync) {
                        SyncService.shared.becameActive()
                    }
                    await NewsService.shared.refresh()
                    await NewsService.shared.send()
                }
            case .inactive:
                AppLock.shared.becameInactive()
            case .background:
                AppLock.shared.movedToBackground()
                LiveActivities.refresh(store: Store.shared)
                SyncService.shared.movedToBackground()
                AppDelegate.scheduleRefresh()
            default:
                break
            }
        }
    }
}
