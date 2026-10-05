import SwiftUI

@main
struct RemaApp: App {
    init() {
        AppFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
