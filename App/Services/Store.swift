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
    private(set) var writeFailed = false

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let shared: Bool
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var widgetSignature: Int?
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onEdit: (() -> Void)?

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
        places.filter { $0.deletedAt == nil && $0.remembered }
    }

    var livePlaces: [Place] {
        places.filter { $0.deletedAt == nil }
    }

    func reminder(_ id: UUID) -> Reminder? {
        reminders.first { $0.id == id }
    }

    func save(_ reminder: Reminder) {
        fresh()
        var updated = reminder
        updated.updatedAt = Date()
        var previous: [UUID] = []
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
            previous = reminders[index].placeIDs
            reminders[index] = updated
        } else {
            reminders.append(updated)
        }
        let kept = updated.deletedAt == nil ? Set(updated.placeIDs) : []
        dropUnusedPlaces(Set(previous + updated.placeIDs).subtracting(kept))
        persist()
    }

    // One-off places live only while a reminder uses them; a day-old orphan comes from an abandoned draft.
    private func dropUnusedPlaces(_ released: Set<UUID>) {
        let used = Set(activeReminders.flatMap(\.placeIDs))
        let stale = Date().addingTimeInterval(-86_400)
        for index in places.indices {
            let place = places[index]
            guard !place.remembered, place.deletedAt == nil, !used.contains(place.id) else { continue }
            if released.contains(place.id) || place.createdAt < stale {
                places[index].deletedAt = Date()
                places[index].updatedAt = Date()
            }
        }
    }

    func complete(_ id: UUID, through occurrence: Date) {
        fresh()
        guard var reminder = reminder(id) else { return }
        reminder.completedThrough = max(reminder.completedThrough ?? occurrence, occurrence)
        reminder.snoozedUntil = nil
        SnoozeStats.reset(id)
        save(reminder)
    }

    func reopen(_ id: UUID, before occurrence: Date) {
        fresh()
        guard var reminder = reminder(id) else { return }
        reminder.completedThrough = occurrence.addingTimeInterval(-1)
        save(reminder)
    }

    func snooze(_ id: UUID, until date: Date) {
        fresh()
        guard var reminder = reminder(id) else { return }
        reminder.snoozedUntil = date
        SnoozeStats.add(id)
        save(reminder)
    }

    func delete(_ id: UUID) {
        fresh()
        guard var reminder = reminder(id) else { return }
        reminder.deletedAt = Date()
        save(reminder)
    }

    // The one-off places a deletion releases, kept so that an undo can bring them back.
    func releasedPlaces(of id: UUID) -> [Place] {
        guard let reminder = reminder(id) else { return [] }
        let others = Set(activeReminders.filter { $0.id != id }.flatMap(\.placeIDs))
        return places.filter { reminder.placeIDs.contains($0.id) && !$0.remembered && $0.deletedAt == nil && !others.contains($0.id) }
    }

    // Undo saves the copies taken before the deletion again; a synced deletion has already removed the tombstone.
    func restore(_ reminder: Reminder, places released: [Place]) {
        fresh()
        for place in released {
            var revived = place
            revived.deletedAt = nil
            save(revived)
        }
        var revived = reminder
        revived.deletedAt = nil
        save(revived)
    }

    func save(_ place: Place) {
        fresh()
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
        fresh()
        guard let index = places.firstIndex(where: { $0.id == id }) else { return }
        places[index].deletedAt = Date()
        places[index].updatedAt = Date()
        for reminder in reminders where reminder.placeIDs.contains(id) {
            var updated = reminder
            updated.placeIDs.removeAll { $0 == id }
            // Without its only place and without a time the reminder would never come again.
            if updated.schedule == nil, updated.placeIDs.isEmpty, updated.deletedAt == nil {
                updated.deletedAt = Date()
            }
            save(updated)
        }
        persist()
    }

    func sound(_ id: UUID) -> CustomSound? {
        sounds.first { $0.id == id }
    }

    func save(_ sound: CustomSound) {
        fresh()
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

    var snapshot: StoreSnapshot {
        StoreSnapshot(reminders: reminders, places: places, settings: settings, sounds: sounds)
    }

    func replace(with snapshot: StoreSnapshot) {
        reminders = snapshot.reminders
        places = snapshot.places
        settings = snapshot.settings
        sounds = snapshot.sounds ?? []
        persist(edit: false)
    }

    func reset() {
        reminders = []
        places = []
        sounds = []
        settings = .standard(at: Date())
        persist(edit: false)
    }

    func update(_ change: (inout Settings) -> Void) {
        fresh()
        change(&settings)
        settings.updatedAt = Date()
        settings.touched = true
        persist()
    }

    // A guest's deletions have no copy on a server to remove, so old ones are dropped instead of piling up.
    func dropTombstones(before date: Date) {
        fresh()
        let count = reminders.count + places.count + sounds.count
        reminders.removeAll { ($0.deletedAt ?? .distantFuture) < date }
        places.removeAll { ($0.deletedAt ?? .distantFuture) < date }
        sounds.removeAll { ($0.deletedAt ?? .distantFuture) < date }
        guard reminders.count + places.count + sounds.count != count else { return }
        persist(edit: false)
    }

    @discardableResult
    func reloadIfChanged(edit: Bool = true) -> Bool {
        guard changedOnDisk else { return false }
        load()
        onChange?()
        if edit {
            onEdit?()
        }
        // The share sheet and the watch write the file without asking the widgets to redraw.
        if shared {
            reloadWidgetsIfNeeded()
        }
        return true
    }

    private var changedOnDisk: Bool {
        guard let modified = SharedStore.modified(in: directory) else { return false }
        return modified != loadedAt
    }

    // The widget, the share sheet and the watch write the same file while this copy sits in memory.
    private func fresh() {
        if changedOnDisk {
            load()
        }
    }

    private func load() {
        guard let snapshot = SharedStore.load(from: directory) else { return }
        reminders = snapshot.reminders
        places = snapshot.places
        settings = snapshot.settings
        sounds = snapshot.sounds ?? []
        loadedAt = SharedStore.modified(in: directory)
    }

    private func persist(edit: Bool = true) {
        // A full disk keeps the change only in memory; the home screen says so instead of losing it quietly.
        do {
            try SharedStore.save(snapshot, to: directory)
            if writeFailed {
                writeFailed = false
            }
        } catch {
            writeFailed = true
        }
        loadedAt = SharedStore.modified(in: directory)
        onChange?()
        if edit {
            onEdit?()
        }
        if shared {
            reloadWidgetsIfNeeded()
        }
    }

    // Widgets show reminders and places only, so a change of settings or sounds does not redraw them.
    private func reloadWidgetsIfNeeded() {
        var hasher = Hasher()
        hasher.combine(reminders)
        hasher.combine(places)
        let signature = hasher.finalize()
        guard signature != widgetSignature else { return }
        widgetSignature = signature
        WidgetCenter.shared.reloadAllTimelines()
    }
}
