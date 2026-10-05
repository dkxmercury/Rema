import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct ListenControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "uz.dkx.rema.listen") {
            ControlWidgetButton(action: ListenIntent()) {
                Label("Say a reminder", systemImage: "mic.fill")
            }
            .tint(Palette.accent)
        }
        .displayName("Say a reminder")
        .description("Opens Rema already listening.")
    }
}

@available(iOS 18.0, *)
struct ComposeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "uz.dkx.rema.compose") {
            ControlWidgetButton(action: ComposeIntent()) {
                Label("New reminder", systemImage: "plus")
            }
            .tint(Palette.accent)
        }
        .displayName("New reminder")
        .description("Opens Rema with the keyboard ready.")
    }
}
