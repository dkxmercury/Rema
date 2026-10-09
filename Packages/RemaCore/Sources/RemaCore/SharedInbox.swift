import Foundation

// Shared reminders that came by push while Rema was closed. The push extension leaves each one here as a file of its own
// and never writes the store, so it cannot overwrite a change the app is saving at that moment; the app takes them in when it runs.
public enum SharedInbox {
    private static let folderName = "inbox"

    public static func add(_ item: SharedItem, in directory: URL = SharedStore.directory, now: Date = Date()) throws {
        let folder = directory.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The time first, so the names sort in the order the pushes came.
        let stamp = String(max(0, now.milliseconds))
        let name = String(repeating: "0", count: max(0, 15 - stamp.count)) + stamp + "-" + UUID().uuidString + ".json"
        try JSONEncoder().encode(item).write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    public static func items(in directory: URL = SharedStore.directory) -> [SharedItem] {
        files(in: directory).compactMap(read)
    }

    // Each file goes once it is read; a push that comes meanwhile stays for the next time.
    public static func take(from directory: URL = SharedStore.directory) -> [SharedItem] {
        files(in: directory).compactMap { url in
            defer { try? FileManager.default.removeItem(at: url) }
            return read(url)
        }
    }

    public static func clear(in directory: URL = SharedStore.directory) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(folderName, isDirectory: true))
    }

    // The reminders as the app will have them once it takes the waiting items in.
    public static func overlaid(_ snapshot: StoreSnapshot?, in directory: URL = SharedStore.directory, now: Date = Date()) -> StoreSnapshot? {
        guard var snapshot else { return nil }
        let items = items(in: directory)
        guard !items.isEmpty else { return snapshot }
        let unconfirmed = SharedMerge.unconfirmed(snapshot.reminders, acknowledged: SharedLedger.acknowledged)
        snapshot.reminders = SharedMerge.apply(items, to: snapshot.reminders, waiting: SharedLedger.waiting, unconfirmed: unconfirmed, now: now)
        return snapshot
    }

    private static func files(in directory: URL) -> [URL] {
        let folder = directory.appendingPathComponent(folderName, isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().map { folder.appendingPathComponent($0) }
    }

    private static func read(_ url: URL) -> SharedItem? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SharedItem.self, from: data)
    }
}
