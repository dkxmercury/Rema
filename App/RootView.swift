import RemaCore
import SwiftUI

struct EditingTarget: Identifiable {
    let id = UUID()
    let reminder: Reminder
    let isNew: Bool
}

struct ComposeTarget: Identifiable {
    let id = UUID()
    let voice: Bool
}

enum RootRoute: Hashable {
    case settings
}

struct RootView: View {
    @State private var store = Store.shared
    @State private var path: [RootRoute] = []
    @State private var editing: EditingTarget?
    @State private var composing: ComposeTarget?
    @State private var showingCalendar = false
    @Namespace private var zoom

    var body: some View {
        PushStack(path: $path) {
            home
        } destination: { route in
            switch route {
            case .settings:
                SettingsScreen(store: store, onBack: { path.removeLast() })
            }
        }
        .fullScreenCover(item: $editing) { target in
            EditorScreen(draft: target.reminder, isNew: target.isNew, store: store, onClose: { editing = nil })
        }
        .fullScreenCover(item: $composing) { target in
            PhraseScreen(store: store, startWithVoice: target.voice, onClose: { composing = nil })
        }
        .fullScreenCover(isPresented: $showingCalendar) {
            CalendarScreen(store: store, onClose: { showingCalendar = false })
                .zoomDestination("calendar", in: zoom)
        }
        .preferredColorScheme(colorScheme)
    }

    private var colorScheme: ColorScheme? {
        switch store.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var home: some View {
        TimelineView(.everyMinute) { timeline in
            HomeScreen(
                content: HomeContent.make(
                    reminders: store.reminders,
                    places: store.places,
                    now: timeline.date,
                    calendar: .current,
                    locale: .current
                ),
                onToggle: toggle,
                onOpen: open,
                onCompose: { composing = ComposeTarget(voice: false) },
                onVoice: {
                    Feedback.play(.select)
                    composing = ComposeTarget(voice: true)
                },
                onCalendar: { showingCalendar = true },
                onSettings: { path.append(.settings) },
                zoom: zoom
            )
        }
    }

    private func toggle(_ row: HomeContent.Row) {
        Feedback.play(row.done ? .uncheck : .check)
        withAnimation(Motion.standard) {
            if row.done {
                store.reopen(row.reminderID, before: row.occurrence)
            } else {
                store.complete(row.reminderID, through: row.occurrence)
            }
        }
    }

    private func open(_ id: UUID) {
        guard let reminder = store.reminder(id) else { return }
        editing = EditingTarget(reminder: reminder, isNew: false)
    }
}
