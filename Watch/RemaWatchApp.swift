import SwiftUI

@main
struct RemaWatchApp: App {
    @State private var model = WatchModel()

    init() {
        AppFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            WatchHome(model: model)
        }
    }
}
