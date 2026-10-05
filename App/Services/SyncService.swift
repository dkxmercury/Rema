import AVFoundation
import Foundation
import Observation
import RemaCore

@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()

    enum Status: Equatable {
        case idle
        case syncing
        case saved
        case offline
        case failed
    }

    private(set) var status: Status = .idle
    private(set) var savedAt: Date?

    @ObservationIgnored private var state: SyncState
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var current: Task<Void, Never>?
    @ObservationIgnored private var again = false
    @ObservationIgnored private let realtime = Realtime()

    private static let pageLimit = 250

    private static var stateURL: URL {
        SharedStore.localDirectory.appendingPathComponent("sync.json")
    }

    private init() {
        state = (try? JSONDecoder().decode(SyncState.self, from: Data(contentsOf: Self.stateURL))) ?? SyncState()
        savedAt = state.lastSync
    }

    var hasPendingChanges: Bool {
        !SyncPlan.changes(in: Store.shared.snapshot, state: state, limit: 1).isEmpty
    }

    func schedule(after delay: Duration = .seconds(2)) {
        guard Account.shared.isSignedIn else { return }
        scheduled?.cancel()
        scheduled = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await run()
        }
    }

    func run() async {
        guard current == nil else {
            again = true
            return
        }
        repeat {
            again = false
            let task = Task { await perform() }
            current = task
            await task.value
            current = nil
        } while again
    }

    func flush() async -> Bool {
        while let current {
            await current.value
        }
        await perform()
        return !hasPendingChanges
    }

    func becameActive() {
        guard Account.shared.isSignedIn else { return }
        realtime.start()
        schedule(after: .zero)
    }

    func movedToBackground() {
        realtime.stop()
    }

    func signOut(discardingChanges: Bool) async -> Bool {
        if !discardingChanges, Account.shared.isSignedIn, !(await flush()) {
            return false
        }
        Account.shared.signOut()
        forgetAccount()
        return true
    }

    func deleteAccount() async throws {
        try await Account.shared.deleteAccount()
        forgetAccount()
    }

    private func forgetAccount() {
        realtime.stop()
        scheduled?.cancel()
        Self.clearLocal()
        state = SyncState()
        saveState()
        savedAt = nil
        status = .idle
    }

    private static func clearLocal() {
        Store.shared.reset()
        SoundSync.removeCustomFiles()
    }

    private func perform() async {
        guard let session = Account.shared.session else { return }
        status = .syncing
        if state.account != session.userID {
            // Data left by another account must not leak into this one; a guest's data moves in.
            if state.account != nil {
                Self.clearLocal()
            }
            state = SyncState(account: session.userID)
        }
        let full = state.needsFullResync(now: Date())
        if full {
            state.cursor = 0
        }
        var seen = Set<String>()
        do {
            for _ in 0..<40 {
                let changes = SyncPlan.changes(in: Store.shared.snapshot, state: state, limit: Self.pageLimit)
                let request = SyncRequest(since: state.cursor, changes: changes)
                let response = try await Backend.request("POST", "/api/rema/sync", body: request, token: session.token, as: SyncResponse.self)
                guard Account.shared.session?.userID == session.userID else { return }
                if full {
                    seen.formUnion(response.records.map { "\($0.kind)/\($0.clientId)" })
                }
                let outcome = SyncMerge.apply(response, sent: changes, to: Store.shared.snapshot, state: state, now: Date())
                state = outcome.state
                if outcome.changed {
                    Store.shared.replace(with: outcome.snapshot)
                }
                saveState()
                await SoundSync.exchange(outcome.soundFiles, token: session.token)
                if !response.more && changes.count < Self.pageLimit {
                    break
                }
            }
            if full {
                let outcome = SyncMerge.reconcile(Store.shared.snapshot, state: state, seen: seen)
                state = outcome.state
                if outcome.changed {
                    Store.shared.replace(with: outcome.snapshot)
                }
                saveState()
            }
            savedAt = Date()
            status = .saved
        } catch Backend.Failure.unauthorized {
            Account.shared.expire()
            realtime.stop()
            status = .failed
        } catch Backend.Failure.offline {
            status = .offline
        } catch {
            status = .failed
        }
    }

    private func saveState() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: Self.stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.stateURL, options: .atomic)
    }
}

@MainActor
private final class Realtime {
    private var task: Task<Void, Never>?

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 3600
        return URLSession(configuration: configuration)
    }()

    func start() {
        guard task == nil else { return }
        task = Task { await loop() }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func loop() async {
        while !Task.isCancelled {
            guard let token = Account.shared.session?.token else { break }
            try? await listen(token: token)
            try? await Task.sleep(for: .seconds(10))
        }
        task = nil
    }

    // Another phone saved something; the event only says when, the sync itself fetches what.
    private func listen(token: String) async throws {
        var request = URLRequest(url: Backend.base.appending(path: "/api/realtime"))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, _) = try await Self.session.bytes(for: request)
        var event = ""
        for try await line in bytes.lines {
            if line.hasPrefix("event:") {
                event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                if event == "PB_CONNECT" {
                    struct Connect: Decodable {
                        let clientId: String
                    }
                    guard let connect = try? JSONDecoder().decode(Connect.self, from: Data(line.dropFirst(5).utf8)) else { continue }
                    struct Body: Encodable {
                        let clientId: String
                        let subscriptions: [String]
                    }
                    try await Backend.send("POST", "/api/realtime", body: Body(clientId: connect.clientId, subscriptions: SyncKind.allCases.map(\.rawValue)), token: token)
                } else if !event.isEmpty {
                    SyncService.shared.schedule(after: .milliseconds(1500))
                }
            }
        }
    }
}

enum SoundSync {
    private static let limit = 1_000_000

    @MainActor
    static func exchange(_ files: [UUID: String], token: String) async {
        for (id, remote) in files {
            let local = SoundLibrary.folder.appendingPathComponent(CustomSound(id: id, name: "", duration: 0, createdAt: Date()).fileName)
            let exists = FileManager.default.fileExists(atPath: local.path)
            if remote.isEmpty, exists {
                try? await upload(id, from: local, token: token)
            } else if !remote.isEmpty, !exists {
                try? await download(id, to: local, token: token)
            }
        }
    }

    static func removeCustomFiles() {
        let folder = SoundLibrary.folder
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasPrefix("custom-") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private static func upload(_ id: UUID, from local: URL, token: String) async throws {
        let compact = try compacted(local)
        defer { try? FileManager.default.removeItem(at: compact) }
        let file = try Data(contentsOf: compact)
        guard file.count <= limit else { return }
        let boundary = "rema-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"sound.caf\"\r\nContent-Type: audio/x-caf\r\n\r\n".utf8))
        body.append(file)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        _ = try await Backend.raw("PUT", "/api/rema/sounds/\(id.uuidString)/file", body: body, contentType: "multipart/form-data; boundary=\(boundary)", token: token)
    }

    private static func download(_ id: UUID, to local: URL, token: String) async throws {
        let data = try await Backend.raw("GET", "/api/rema/sounds/\(id.uuidString)/file", token: token)
        try FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: local, options: .atomic)
    }

    // Thirty seconds of uncompressed stereo is about 5 MB; IMA4 mono keeps it under the 1 MB the account allows.
    private static func compacted(_ source: URL) throws -> URL {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: mono),
              let original = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(input.length)),
              let converted = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(input.length))
        else { throw CocoaError(.fileReadCorruptFile) }
        try input.read(into: original)
        var delivered = false
        var failure: NSError?
        converter.convert(to: converted, error: &failure) { _, status in
            if delivered {
                status.pointee = .endOfStream
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return original
        }
        if let failure {
            throw failure
        }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleIMA4,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        let output = try AVAudioFile(forWriting: target, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try output.write(from: converted)
        return target
    }
}
