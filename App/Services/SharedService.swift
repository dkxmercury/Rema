import Foundation
import Observation
import RemaCore

// Friends and reminders shared with them. Every change waits in an outbox until the server takes it,
// so a reminder made without a connection reaches the friends later. The names I give friends never leave this phone.
@MainActor
@Observable
final class SharedService {
    static let shared = SharedService()

    struct Friend: Codable, Identifiable, Hashable {
        let id: String
        var name: String
        var since: Date
    }

    struct SentInvite: Codable, Identifiable, Hashable {
        var id: String { code }
        let code: String
        var state: String
        var expires: Date
        var friendID: String?
    }

    enum Op: Codable, Equatable {
        case create(id: String, data: SharedData, members: [String], stamp: Int64)
        case update(id: String, data: SharedData, members: [String], stamp: Int64)
        case delete(id: String)
        case respond(id: String, accept: Bool)
        case leave(id: String)
        case done(id: String, through: Int64)

        var id: String {
            switch self {
            case .create(let id, _, _, _), .update(let id, _, _, _), .delete(let id), .respond(let id, _), .leave(let id), .done(let id, _):
                return id
            }
        }
    }

    struct State: Codable {
        var account: String?
        var cursor: Int64 = 0
        var friends: [Friend] = []
        var invites: [SentInvite] = []
        var names: [String: String] = [:]
        var pendingNames: [String: String] = [:]
        var outbox: [Op] = []
        var myName: String?
    }

    struct InviteView: Decodable {
        let code: String
        let state: String
        let expires: Int64
        let own: Bool
        let inviter: SharedPerson
    }

    private(set) var state = State()
    private(set) var problem: Backend.Failure?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var again = false

    private static var stateURL: URL {
        SharedStore.localDirectory.appendingPathComponent("shared-state.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.stateURL), let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        }
        SharedNames.names = state.names
        SharedNames.me = state.account
    }

    private func save() {
        SharedNames.names = state.names
        SharedNames.me = state.account
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: Self.stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.stateURL, options: .atomic)
    }

    var friends: [Friend] {
        state.friends.sorted { name(of: $0.id, fallback: $0.name).localizedCaseInsensitiveCompare(name(of: $1.id, fallback: $1.name)) == .orderedAscending }
    }

    var waiting: Set<UUID> {
        Set(state.outbox.compactMap { UUID(uuidString: $0.id) })
    }

    var myName: String {
        state.myName ?? ""
    }

    // The name I gave a friend wins over the one they gave themselves.
    func name(of id: String, fallback: String) -> String {
        _ = state.names
        return SharedNames.name(of: id, fallback: fallback)
    }

    func rename(_ id: String, to name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        state.names[id] = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func reset() {
        running?.cancel()
        running = nil
        state = State()
        problem = nil
        save()
    }

    // One pass at a time; a request during it runs once more right after.
    func refresh() async {
        if let running {
            again = true
            await running.value
            return
        }
        let task = Task { @MainActor in
            repeat {
                again = false
                await perform()
            } while again
            running = nil
        }
        running = task
        await task.value
    }

    func kick() {
        Task { await refresh() }
    }

    private func perform() async {
        guard Remote.shared.isOn(.sync), let session = Account.shared.session else { return }
        if state.account != session.userID {
            state = State(account: session.userID)
            save()
        }
        do {
            try await flush(token: session.token)
            for _ in 0..<20 {
                struct Since: Encodable { let since: Int64 }
                struct Answer: Decodable {
                    let items: [SharedItem]?
                    let cursor: Int64
                    let more: Bool?
                }
                let answer = try await Backend.request("POST", "/api/rema/shared/sync", body: Since(since: state.cursor), token: session.token, as: Answer.self)
                guard Account.shared.session?.userID == session.userID else { return }
                Store.shared.applyShared(answer.items ?? [], waiting: waiting)
                state.cursor = answer.cursor
                save()
                if answer.more != true {
                    break
                }
            }
            try await loadFriends(token: session.token)
            problem = nil
        } catch let failure as Backend.Failure {
            problem = failure
        } catch {
            problem = .server
        }
    }

    private func flush(token: String) async throws {
        while let op = state.outbox.first {
            do {
                let item = try await send(op, token: token)
                state.outbox.removeFirst()
                save()
                if let item {
                    Store.shared.applyShared([item], waiting: waiting)
                }
            } catch let failure as Backend.Failure {
                switch failure {
                case .invalid, .conflict:
                    // The server will never take this one, a later sync brings back what it has.
                    state.outbox.removeFirst()
                    save()
                    problem = failure
                default:
                    throw failure
                }
            }
        }
    }

    private func send(_ op: Op, token: String) async throws -> SharedItem? {
        struct Body: Encodable {
            let id: String
            let data: SharedData
            let clientUpdatedAt: Int64
            let members: [String]
        }
        struct Answer: Encodable { let accept: Bool }
        struct Through: Encodable { let through: Int64 }
        switch op {
        case .create(let id, let data, let members, let stamp):
            return try await Backend.request("POST", "/api/rema/shared", body: Body(id: id, data: data, clientUpdatedAt: stamp, members: members), token: token, as: SharedItem.self)
        case .update(let id, let data, let members, let stamp):
            return try await Backend.request("PUT", "/api/rema/shared/\(id)", body: Body(id: id, data: data, clientUpdatedAt: stamp, members: members), token: token, as: SharedItem.self)
        case .delete(let id):
            try await Backend.send("DELETE", "/api/rema/shared/\(id)", token: token)
            return nil
        case .respond(let id, let accept):
            return try await Backend.request("POST", "/api/rema/shared/\(id)/respond", body: Answer(accept: accept), token: token, as: SharedItem.self)
        case .leave(let id):
            try await Backend.send("POST", "/api/rema/shared/\(id)/leave", token: token)
            return nil
        case .done(let id, let through):
            return try await Backend.request("POST", "/api/rema/shared/\(id)/done", body: Through(through: through), token: token, as: SharedItem.self)
        }
    }

    // A newer change of the same kind replaces the one still waiting; a change of a reminder not sent yet goes into its creation.
    private func enqueue(_ op: Op) {
        switch op {
        case .update(let id, let data, let members, _):
            if let index = state.outbox.firstIndex(where: { if case .create(id, _, _, _) = $0 { return true } else { return false } }), case .create(_, _, _, let stamp) = state.outbox[index] {
                state.outbox[index] = .create(id: id, data: data, members: members, stamp: max(stamp, Self.stamp()))
                save()
                return
            }
            state.outbox.removeAll { if case .update(id, _, _, _) = $0 { return true } else { return false } }
        case .done(let id, _):
            state.outbox.removeAll { if case .done(id, _) = $0 { return true } else { return false } }
        case .delete(let id):
            let unsent = state.outbox.contains { if case .create(id, _, _, _) = $0 { return true } else { return false } }
            state.outbox.removeAll { $0.id == id }
            if unsent {
                save()
                return
            }
        default:
            break
        }
        state.outbox.append(op)
        save()
    }

    private static func stamp() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }


    func create(_ reminder: Reminder, with members: [SharedPerson], doneMode: DoneMode) {
        guard let session = Account.shared.session else { return }
        var local = reminder
        if var schedule = local.schedule, schedule.timeZone == nil {
            schedule.timeZone = TimeZone.current.identifier
            local.schedule = schedule
        }
        local.shared = SharedInfo(
            owner: SharedPerson(id: session.userID, name: myName),
            status: SharedStatus.owner,
            members: members.map { SharedMember(id: $0.id, name: $0.name, status: SharedStatus.invited) },
            doneMode: doneMode,
            pending: true
        )
        Store.shared.save(local)
        enqueue(.create(id: local.id.uuidString, data: local.sharedData, members: members.map(\.id), stamp: Self.stamp()))
        kick()
    }

    func changed(_ reminder: Reminder) {
        guard let shared = reminder.shared, shared.isMine else { return }
        let members = shared.members.filter { $0.status == SharedStatus.invited || $0.status == SharedStatus.accepted }.map(\.id)
        enqueue(.update(id: reminder.id.uuidString, data: reminder.sharedData, members: members, stamp: Self.stamp()))
        kick()
    }

    func ticked(_ reminder: Reminder) {
        guard let shared = reminder.shared, !shared.isInvitation else { return }
        let through = reminder.completedThrough.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) } ?? 0
        enqueue(.done(id: reminder.id.uuidString, through: through))
        kick()
    }

    func removed(_ reminder: Reminder) {
        guard let shared = reminder.shared else { return }
        enqueue(shared.isMine ? .delete(id: reminder.id.uuidString) : .leave(id: reminder.id.uuidString))
        kick()
    }

    func respond(_ id: UUID, accept: Bool) {
        Store.shared.answerInvitation(id, accept: accept)
        enqueue(.respond(id: id.uuidString, accept: accept))
        kick()
    }


    func createInvite(calling name: String) async throws -> (code: String, link: URL) {
        guard let session = Account.shared.session else { throw Backend.Failure.unauthorized }
        struct Created: Decodable {
            let code: String
            let expires: Int64
        }
        let created = try await Backend.request("POST", "/api/rema/invites", token: session.token, as: Created.self)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            state.pendingNames[created.code] = String(trimmed.prefix(40))
        }
        state.invites.insert(SentInvite(code: created.code, state: "open", expires: Date(timeIntervalSince1970: Double(created.expires) / 1000)), at: 0)
        save()
        return (created.code, Self.link(created.code))
    }

    static func link(_ code: String) -> URL {
        URL(string: "https://remaapp.cc/i/\(code)")!
    }

    func setPendingName(_ code: String, _ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        state.pendingNames[code] = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func pendingName(_ code: String) -> String? {
        state.pendingNames[code]
    }

    func invite(_ code: String) async throws -> InviteView {
        guard let session = Account.shared.session else { throw Backend.Failure.unauthorized }
        return try await Backend.request("GET", "/api/rema/invites/\(code)", token: session.token, as: InviteView.self)
    }

    func accept(_ code: String) async throws {
        guard let session = Account.shared.session else { throw Backend.Failure.unauthorized }
        struct Accepted: Decodable { let friend: SharedPerson }
        let accepted = try await Backend.request("POST", "/api/rema/invites/\(code)/accept", token: session.token, as: Accepted.self)
        if !state.friends.contains(where: { $0.id == accepted.friend.id }) {
            state.friends.append(Friend(id: accepted.friend.id, name: accepted.friend.name, since: Date()))
            save()
        }
        kick()
    }

    func decline(_ code: String) async {
        guard let session = Account.shared.session else { return }
        try? await Backend.send("POST", "/api/rema/invites/\(code)/decline", token: session.token)
    }

    func revoke(_ code: String) async {
        guard let session = Account.shared.session else { return }
        try? await Backend.send("DELETE", "/api/rema/invites/\(code)", token: session.token)
        state.invites.removeAll { $0.code == code }
        state.pendingNames[code] = nil
        save()
    }

    func remove(_ friendID: String) async throws {
        guard let session = Account.shared.session else { throw Backend.Failure.unauthorized }
        try await Backend.send("DELETE", "/api/rema/friends/\(friendID)", token: session.token)
        forget(friendID)
    }

    func block(_ userID: String) async throws {
        guard let session = Account.shared.session else { throw Backend.Failure.unauthorized }
        struct Body: Encodable { let user: String }
        try await Backend.send("POST", "/api/rema/blocks", body: Body(user: userID), token: session.token)
        forget(userID)
    }

    // Without the friendship nothing is shared any more, here as on the server.
    private func forget(_ userID: String) {
        state.friends.removeAll { $0.id == userID }
        state.names[userID] = nil
        save()
        Store.shared.dropShared(with: userID)
        kick()
    }

    func report(user: String?, shared: UUID?, reason: String) async throws {
        guard let session = Account.shared.session else { throw Backend.Failure.unauthorized }
        struct Body: Encodable {
            let user: String
            let shared: String
            let reason: String
            let text: String
        }
        try await Backend.send("POST", "/api/rema/reports", body: Body(user: user ?? "", shared: shared?.uuidString ?? "", reason: reason, text: ""), token: session.token)
    }

    func setMyName(_ name: String) async throws {
        guard let session = Account.shared.session else { throw Backend.Failure.unauthorized }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        struct Body: Encodable { let name: String }
        try await Backend.send("PATCH", "/api/collections/users/records/\(session.userID)", body: Body(name: trimmed), token: session.token)
        state.myName = trimmed
        save()
    }

    private func loadFriends(token: String) async throws {
        struct Answer: Decodable {
            struct Entry: Decodable {
                let id: String
                let name: String?
                let since: Int64?
            }
            struct Sent: Decodable {
                let code: String
                let state: String
                let expires: Int64
                let friend: SharedPerson?
            }
            let friends: [Entry]?
            let invites: [Sent]?
        }
        let answer = try await Backend.request("GET", "/api/rema/friends", token: token, as: Answer.self)
        state.friends = (answer.friends ?? []).map { Friend(id: $0.id, name: $0.name ?? "", since: Date(timeIntervalSince1970: Double($0.since ?? 0) / 1000)) }
        state.invites = (answer.invites ?? []).map { SentInvite(code: $0.code, state: $0.state, expires: Date(timeIntervalSince1970: Double($0.expires) / 1000), friendID: $0.friend?.id) }
        // The name typed when inviting goes to the friend who took the invitation.
        for invite in answer.invites ?? [] {
            guard let friend = invite.friend, let name = state.pendingNames[invite.code] else { continue }
            if state.names[friend.id] == nil {
                state.names[friend.id] = name
            }
            state.pendingNames[invite.code] = nil
        }
        save()
    }
}
