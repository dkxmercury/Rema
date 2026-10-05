import SwiftUI
import WidgetKit

@main
struct RemaWidgets: WidgetBundle {
    init() {
        AppFonts.register()
    }

    var body: some Widget {
        if #available(iOS 18.0, *) {
            return withControls
        } else {
            return widgets
        }
    }

    @WidgetBundleBuilder
    private var widgets: some Widget {
        DialWidget()
        NextWidget()
        TodayWidget()
        ReminderLiveActivity()
    }

    @available(iOS 18.0, *)
    @WidgetBundleBuilder
    private var withControls: some Widget {
        DialWidget()
        NextWidget()
        TodayWidget()
        ReminderLiveActivity()
        ListenControl()
        ComposeControl()
    }
}
