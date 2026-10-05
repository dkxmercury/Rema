import SwiftUI
import WidgetKit

@main
struct RemaWidgets: WidgetBundle {
    init() {
        AppFonts.register()
    }

    var body: some Widget {
        DialWidget()
        NextWidget()
        TodayWidget()
        ReminderLiveActivity()
    }
}
