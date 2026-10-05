import Foundation
import Observation
import RemaCore
import WidgetKit

@Observable
final class Store {
    private(set) var reminders: [Reminder] = []
    private(set) var places: [Place] = []
    private(set) var sounds: [CustomSound] = []
    private(set) var settings: Settings

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let shared: Bool
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored var onChange: (() -> Void)?

    init(directory: URL? = nil) {
        if directory == nil {
            SharedStore.moveLocalFileToGroup()
        }
        self.directory = directory ?? SharedStore.directory
        shared = directory == nil
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        settings = .standard(at: Date())
        load()
    }

    var activeReminders: [Reminder] {
        reminders.filter { $0.deletedAt == nil }
    }

    var activePlaces: [Place] {
        places.filter { $0.deletedAt == nil }
    }

    func reminder(_ id: UUID) -> Reminder? {
        reminders.first { $0.id == id }
    }

    func save(_ reminder: Reminder) {
        var updated = reminder
        updated.updatedAt = Date()
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
            reminders[index] = updated
        } else {
            reminders.append(updated)
        }
        persist()
    }

    func complete(_ id: UUID, through occurrence: Date) {
        guard var reminder = reminder(id) else { return }
        reminder.completedThrough = max(reminder.completedThrough ?? occurrence, occurrence)
        reminder.snoozedUntil = nil
        save(reminder)
    }

    func reopen(_ id: UUID, before occurrence: Date) {
        guard var reminder = reminder(id) else { return }
        reminder.completedThrough = occurrence.addingTimeInterval(-1)
        save(reminder)
    }

    func snooze(_ id: UUID, until date: Date) {
        guard var reminder = reminder(id) else { return }
        reminder.snoozedUntil = date
        save(reminder)
    }

    func delete(_ id: UUID) {
        guard var reminder = reminder(id) else { return }
        reminder.deletedAt = Date()
        save(reminder)
    }

    func save(_ place: Place) {
        var updated = place
        updated.updatedAt = Date()
        if let index = places.firstIndex(where: { $0.id == place.id }) {
            places[index] = updated
        } else {
            places.append(updated)
        }
        persist()
    }

    func deletePlace(_ id: UUID) {
        guard let index = places.firstIndex(where: { $0.id == id }) else { return }
        places[index].deletedAt = Date()
        places[index].updatedAt = Date()
        for reminder in reminders where reminder.placeIDs.contains(id) {
            var updated = reminder
            updated.placeIDs.removeAll { $0 == id }
            save(updated)
        }
        persist()
    }

    func sound(_ id: UUID) -> CustomSound? {
        sounds.first { $0.id == id }
    }

    func save(_ sound: CustomSound) {
        if let index = sounds.firstIndex(where: { $0.id == sound.id }) {
            sounds[index] = sound
        } else {
            sounds.append(sound)
        }
        persist()
    }

    func seed(reminders: [Reminder], places: [Place], sounds: [CustomSound]) {
        self.reminders = reminders
        self.places = places
        self.sounds = sounds
        persist()
    }

    static let shared = Store()

    func update(_ change: (inout Settings) -> Void) {
        change(&settings)
        settings.updatedAt = Date()
        persist()
    }

    func reloadIfChanged() {
        guard let modified = SharedStore.modified(in: directory), modified != loadedAt else { return }
        load()
        onChange?()
    }

    private func load() {
        guard let snapshot = SharedStore.load(from: directory) else { return }
        reminders = snapshot.reminders
        places = snapshot.places
        settings = snapshot.settings
        sounds = snapshot.sounds ?? []
        loadedAt = SharedStore.modified(in: directory)
    }

    private func persist() {
        let snapshot = StoreSnapshot(reminders: reminders, places: places, settings: settings, sounds: sounds)
        try? SharedStore.save(snapshot, to: directory)
        loadedAt = SharedStore.modified(in: directory)
        onChange?()
        if shared {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
