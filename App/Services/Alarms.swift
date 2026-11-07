import ActivityKit
import AlarmKit
import AppIntents
import CryptoKit
import Foundation
import RemaCore
import SwiftUI
import UIKit

@available(iOS 26.0, *)
struct ReminderAlarm: AlarmMetadata {}

// The rings of persistent reminders go off as full-screen alarms; whatever the phone refuses stays a notification.
@available(iOS 26.0, *)
enum Alarms {
    private static let ringsKey = "alarms.rings"

    static var refused: Bool {
        AlarmManager.shared.authorizationState == .denied
    }

    // Asked only on screen and only when there is something to ring for; a rebuild in the background never asks.
    @MainActor
    static func ask(for reminders: [Reminder]) async -> Bool {
        guard AlarmManager.shared.authorizationState == .notDetermined,
              UIApplication.shared.applicationState == .active,
              reminders.contains(where: { $0.isLive && $0.nag }) else { return false }
        return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
    }

    static func stop(_ id: UUID) {
        try? AlarmManager.shared.stop(id: id)
    }

    // Returns the rings the alarms took over, so the same moments do not come as notifications too.
    @MainActor
    static func sync(_ rings: [PlannedNotification], store: Store) async -> Set<String> {
        let manager = AlarmManager.shared
        let existing = (try? manager.alarms) ?? []
        let known = UserDefaults.standard.dictionary(forKey: ringsKey) as? [String: String] ?? [:]
        var wanted: [(id: UUID, ring: PlannedNotification, reminder: Reminder, sound: String)] = []
        if manager.authorizationState == .authorized {
            for ring in rings {
                guard let reminder = store.reminder(ring.reminderID), let sound = soundFile(reminder, store: store) else { continue }
                wanted.append((id(ring, reminder: reminder, sound: sound, store: store), ring, reminder, sound))
            }
        }
        let wantedIDs = Set(wanted.map(\.id))
        var kept: [String: String] = [:]
        for alarm in existing where !wantedIDs.contains(alarm.id) {
            // A ring going off right now stays until its reminder is marked, otherwise opening Rema would silence it.
            if alarm.state == .alerting, let entry = known[alarm.id.uuidString], due(entry, store: store) {
                kept[alarm.id.uuidString] = entry
                continue
            }
            try? manager.cancel(id: alarm.id)
        }
        let present = Set(existing.map(\.id))
        var covered = Set<String>()
        for item in wanted {
            if !present.contains(item.id) {
                do {
                    _ = try await manager.schedule(id: item.id, configuration: configuration(item.ring, id: item.id, reminder: item.reminder, sound: item.sound, store: store))
                } catch {
                    // Past the system limit the remaining rings come as notifications.
                    break
                }
            }
            covered.insert(item.ring.identifier)
            kept[item.id.uuidString] = "\(item.ring.reminderID.uuidString) \(item.ring.occurrence.timeIntervalSince1970)"
        }
        UserDefaults.standard.set(kept, forKey: ringsKey)
        return covered
    }

    private static func due(_ entry: String, store: Store) -> Bool {
        let parts = entry.split(separator: " ")
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])), let seconds = Double(parts[1]),
              let reminder = store.reminder(id) else { return false }
        return reminder.isLive && reminder.nag && !reminder.isDone(Date(timeIntervalSince1970: seconds))
    }

    @MainActor
    private static func soundFile(_ reminder: Reminder, store: Store) -> String? {
        if let note = VoiceNotes.note(of: reminder, sounds: store.sounds) {
            return note.fileName
        }
        return SoundPlayer.url(for: reminder.sound, settings: store.settings, sounds: store.sounds)?.lastPathComponent
    }

    private static func doneText() -> String {
        String(localized: "Done", bundle: .app, locale: .app)
    }

    private static func laterText(_ reminder: Reminder, store: Store) -> String {
        let minutes = min(max(1, reminder.nagInterval ?? store.settings.nagInterval), 1440)
        return String(localized: "in \(minutes) min", bundle: .app, locale: .app).capitalizedFirst(.current)
    }

    // Everything the alarm shows goes into its id, so a renamed reminder or another language gets a fresh alarm.
    @MainActor
    private static func id(_ ring: PlannedNotification, reminder: Reminder, sound: String, store: Store) -> UUID {
        let content = [ring.identifier, reminder.title, sound, doneText(), laterText(reminder, store: store)].joined(separator: "\n")
        let bytes = Array(SHA256.hash(data: Data(content.utf8)))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    @MainActor
    private static func configuration(_ ring: PlannedNotification, id: UUID, reminder: Reminder, sound: String, store: Store) -> AlarmManager.AlarmConfiguration<ReminderAlarm> {
        let title = LocalizedStringResource(stringLiteral: reminder.title)
        let done = AlarmButton(text: LocalizedStringResource(stringLiteral: doneText()), textColor: Palette.onAccent, systemImageName: "checkmark")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title, secondaryButton: done, secondaryButtonBehavior: .custom)
        } else {
            // Before 26.1 the stop button is ours to name; stopping only waits for the next ring of the series.
            let later = AlarmButton(text: LocalizedStringResource(stringLiteral: laterText(reminder, store: store)), textColor: .white, systemImageName: "clock")
            alert = AlarmPresentation.Alert(title: title, stopButton: later, secondaryButton: done, secondaryButtonBehavior: .custom)
        }
        let attributes = AlarmAttributes<ReminderAlarm>(presentation: AlarmPresentation(alert: alert), metadata: ReminderAlarm(), tintColor: Palette.accent)
        return .alarm(
            schedule: .fixed(ring.fireDate),
            attributes: attributes,
            stopIntent: AlarmStoppedIntent(),
            secondaryIntent: AlarmDoneIntent(alarm: id, reminder: ring.reminderID, occurrence: ring.occurrence),
            sound: .named(sound)
        )
    }
}

struct AlarmDoneIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Done"
    static let isDiscoverable = false

    @Parameter(title: "Alarm")
    var alarm: String

    @Parameter(title: "Reminder")
    var reminder: String

    @Parameter(title: "Occurrence")
    var occurrence: Double

    init() {}

    init(alarm: UUID, reminder: UUID, occurrence: Date) {
        self.alarm = alarm.uuidString
        self.reminder = reminder.uuidString
        self.occurrence = occurrence.timeIntervalSince1970
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: reminder) else { return .result() }
        await Notifier.shared.finishAlarm(id, occurrence: Date(timeIntervalSince1970: occurrence), alarm: UUID(uuidString: alarm))
        return .result()
    }
}

// Stopping a ring does not mark anything; it only gives Rema a moment to drop the rest of the series if the reminder was ticked elsewhere.
struct AlarmStoppedIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await Notifier.shared.reschedule()
        return .result()
    }
}
