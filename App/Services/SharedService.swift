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

        var isCreate: Bool {
            if case .create = self { return true }
            return false
        }

        var isUpdate: Bool {
            if case .update = self { return true }
            return false
        }

        var isDone: Bool {
            if case .done = self { return true }
            return false
        }
    }

    // A change waiting to be sent. The key tells it apart from a newer change of the same reminder made while it was on its way.
    struct Pending: Codable, Equatable {
        var key = UUID()
        var op: Op
        var retried: Bool?
    }

    struct State: Codable {
        var account: String?
        var cursor: Int64 = 0
        var friends: [Friend] = []
        var invites: [SentInvite] = []
        var names: [String: String] = [:]
        var pendingNames: [String: String] = [:]
        var outbox: [Pending] = []
        var myName: String?
        // A reminder the server would not share, told once on the home screen.
        var refused: String?
        // A change the server would not take; the friends keep the reminder as it was.
        var refusedChange: String?
        // The people I blocked, so a block made by mistake can be taken back.
        var blocked: [SharedPerson] = []

        init() {}

        init(account: String?) {
            self.account = account
        }

        // Each part is read on its own, so a file from an older build loses only what changed shape.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            account = try? container.decodeIfPresent(String.self, forKey: .account)
            cursor = (try? container.decodeIfPresent(Int64.self, forKey: .cursor)) ?? 0
            friends = (try? container.decodeIfPresent([Friend].self, forKey: .friends)) ?? []
            invites = (try? container.decodeIfPresent([SentInvite].self, forKey: .invites)) ?? []
            names = (try? container.decodeIfPresent([String: String].self, forKey: .names)) ?? [:]
            pendingNames = (try? container.decodeIfPresent([String: String].self, forKey: .pendingNames)) ?? [:]
            outbox = (try? container.decodeIfPresent([Pending].self, forKey: .outbox)) ?? []
            myName = try? container.decodeIfPresent(String.self, forKey: .myName)
            refused = try? container.decodeIfPresent(String.self, forKey: .refused)
            refusedChange = try? container.decodeIfPresent(String.self, forKey: .refusedChange)
            blocked = (try? container.decodeIfPresent([SharedPerson].self, forKey: .blocked)) ?? []
        }
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
    @ObservationIgnored private var sending: UUID?
    // An invitation made on this run and not handed to anybody yet, shown again instead of a new one.
    @ObservationIgnored private var spare: String?

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
        SharedLedger.waiting = waiting
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: Self.stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.stateURL, options: .atomic)
    }

    var friends: [Friend] {
        state.friends.sorted { name(of: $0.id, fallback: $0.name).localizedCaseInsensitiveCompare(name(of: $1.id, fallback: $1.name)) == .orderedAscending }
    }

    var waiting: Set<UUID> {
        Set(state.outbox.compactMap { UUID(uuidString: $0.op.id) })
    }

    // Until it is changed here, friends see the name the account already has.
    var myName: String {
        state.myName ?? Account.shared.session?.name ?? ""
    }

    var hasUnsent: Bool {
        !state.outbox.isEmpty
    }

    // The name I gave a friend wins over the one they gave themselves.
    func name(of id: String, fallback: String) -> String {
        SharedNames.name(of: id, fallback: fallback, known: state.names)
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
        spare = nil
        SharedLedger.clear()
        SharedInbox.clear()
        save()
    }

    #if DEBUG
    func useDemo(friends: [Friend], myName: String) {
        state = State(account: "demo")
        state.friends = friends
        state.myName = myName
        save()
    }
    #endif

    func clearRefused() {
        state.refused = nil
        state.refusedChange = nil
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
        #if DEBUG
        // The demo has no server: a new shared reminder counts as delivered at once.
        if DemoMode.isOn {
            for entry in state.outbox {
                guard case .create(let id, _, _, _) = entry.op, let uuid = UUID(uuidString: id), var reminder = Store.shared.reminder(uuid) else { continue }
                reminder.shared?.pending = false
                Store.shared.save(reminder)
            }
            state.outbox = []
            save()
            return
        }
        #endif
        guard Remote.shared.isOn(.sync), let session = Account.shared.session else { return }
        if state.account != session.userID {
            state = State(account: session.userID)
            spare = nil
            SharedLedger.clear()
            SharedInbox.clear()
            save()
        }
        let account = session.userID
        Store.shared.absorbInbox()
        reconcileTicks()
        var trouble: Backend.Failure?
        do {
            trouble = try await flush(token: session.token, account: account)
        } catch let failure as Backend.Failure {
            problem = failure
            return
        } catch {
            problem = .server
            return
        }
        // The reminders and friends come in even when some change is still stuck in the outbox.
        do {
            for _ in 0..<20 {
                struct Since: Encodable { let since: Int64 }
                struct Answer: Decodable {
                    let items: [SharedItem]?
                    let cursor: Int64
                    let more: Bool?
                }
                let answer = try await Backend.request("POST", "/api/rema/shared/sync", body: Since(since: state.cursor), token: session.token, as: Answer.self)
                guard state.account == account, Account.shared.session?.userID == account else { return }
                let skipped = waiting
                let items = answer.items ?? []
                SharedLedger.record(items.filter { !(UUID(uuidString: $0.id).map(skipped.contains) ?? false) })
                Store.shared.applyShared(items, waiting: skipped)
                state.cursor = answer.cursor
                save()
                if answer.more != true {
                    break
                }
            }
            try await loadFriends(token: session.token, account: account)
            problem = trouble
        } catch let failure as Backend.Failure {
            problem = failure
        } catch {
            problem = .server
        }
    }

    // Sends the waiting changes in order. A reminder whose change meets a passing problem waits with its later changes
    // while the other reminders go on; a change the server will never take is dropped.
    private func flush(token: String, account: String) async throws -> Backend.Failure? {
        var held = Set<String>()
        var trouble: Backend.Failure?
        for key in state.outbox.map(\.key) {
            // A change rewritten while the ones before it were sent goes out as it is now.
            guard let entry = state.outbox.first(where: { $0.key == key }), !held.contains(entry.op.id) else { continue }
            sending = entry.key
            defer { sending = nil }
            do {
                let item = try await send(entry.op, token: token)
                guard state.account == account else { return nil }
                state.outbox.removeAll { $0.key == entry.key }
                // The server had this reminder already from a send whose answer got lost, without the later change.
                if case .create(let id, let data, let members, let stamp) = entry.op, let item, item.clientUpdatedAt < stamp {
                    enqueue(.update(id: id, data: data, members: members, stamp: stamp))
                    again = true
                }
                save()
                guard let item else { continue }
                let skipped = waiting
                if !(UUID(uuidString: item.id).map(skipped.contains) ?? false) {
                    SharedLedger.record([item])
                }
                Store.shared.applyShared([item], waiting: skipped)
            } catch let failure as Backend.Failure where failure.isRefusal {
                guard state.account == account else { return nil }
                // Someone in it stopped being a friend since; with the friends read again it goes once more without them.
                if failure == .invalid("not_friend"), entry.retried != true, entry.op.isCreate || entry.op.isUpdate {
                    try? await loadFriends(token: token, account: account)
                    if let index = state.outbox.firstIndex(where: { $0.key == entry.key }) {
                        state.outbox[index].retried = true
                        save()
                    }
                    held.insert(entry.op.id)
                    again = true
                    continue
                }
                state.outbox.removeAll { $0.key == entry.key }
                switch entry.op {
                case .create(let id, let data, _, _):
                    state.outbox.removeAll { $0.op.id == id }
                    if let uuid = UUID(uuidString: id) {
                        Store.shared.unshare(uuid)
                    }
                    state.refused = data.title
                case .update(_, let data, _, _):
                    state.refusedChange = data.title
                default:
                    break
                }
                // What the server has for this reminder is unknown here now, so the next pass reads everything again.
                state.cursor = 0
                save()
                trouble = failure
            } catch let failure as Backend.Failure {
                if failure == .offline || failure == .unauthorized {
                    throw failure
                }
                held.insert(entry.op.id)
                trouble = failure
            }
        }
        return trouble
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
            return try await Backend.request("POST", "/api/rema/shared", body: Body(id: id, data: data, clientUpdatedAt: stamp, members: stillFriends(members)), token: token, as: SharedItem.self)
        case .update(let id, let data, let members, let stamp):
            return try await Backend.request("PUT", "/api/rema/shared/\(id)", body: Body(id: id, data: data, clientUpdatedAt: stamp, members: stillFriends(members)), token: token, as: SharedItem.self)
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

    // Someone who stopped being a friend since would make the server refuse the whole reminder.
    private func stillFriends(_ members: [String]) -> [String] {
        guard !state.friends.isEmpty else { return members }
        let known = Set(state.friends.map(\.id))
        return members.filter(known.contains)
    }

    // A tick made in the widget, on the watch or from a notification while Rema was closed reaches no hook, so it is noticed here.
    private func reconcileTicks() {
        for id in SharedMerge.unconfirmed(Store.shared.reminders, acknowledged: SharedLedger.acknowledged) {
            guard let reminder = Store.shared.reminder(id), !state.outbox.contains(where: { $0.op.id == id.uuidString && $0.op.isDone }) else { continue }
            enqueue(.done(id: id.uuidString, through: Self.milliseconds(reminder.completedThrough)))
        }
    }

    // A newer change of the same kind replaces the one still waiting, and a change of a reminder not sent yet goes into its creation.
    // The change on its way right now is never touched, whatever comes after it is sent after it.
    private func enqueue(_ op: Op) {
        let id = op.id
        let current = sending
        func waitingHere(_ entry: Pending) -> Bool {
            entry.key != current && entry.op.id == id
        }
        switch op {
        case .update(_, let data, let members, _):
            if let index = state.outbox.firstIndex(where: { waitingHere($0) && $0.op.isCreate }), case .create(_, _, _, let stamp) = state.outbox[index].op {
                state.outbox[index].op = .create(id: id, data: data, members: members, stamp: max(stamp, Self.stamp()))
                save()
                return
            }
            state.outbox.removeAll { waitingHere($0) && $0.op.isUpdate }
        case .done:
            state.outbox.removeAll { waitingHere($0) && $0.op.isDone }
        case .delete:
            let unsent = state.outbox.contains { waitingHere($0) && $0.op.isCreate }
            state.outbox.removeAll(where: waitingHere)
            // Nothing reached the server, so nothing has to be deleted there.
            if unsent {
                save()
                return
            }
        default:
            break
        }
        state.outbox.append(Pending(op: op))
        save()
    }

    private static func stamp() -> Int64 {
        milliseconds(Date())
    }

    static func milliseconds(_ date: Date?) -> Int64 {
        date?.milliseconds ?? 0
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
        enqueue(.done(id: reminder.id.uuidString, through: Self.milliseconds(reminder.completedThrough)))
        kick()
    }

    func removed(_ reminder: Reminder) {
        guard let shared = reminder.shared else { return }
        SharedLedger.forget(reminder.id.uuidString)
        enqueue(shared.isMine ? .delete(id: reminder.id.uuidString) : .leave(id: reminder.id.uuidString))
        kick()
    }

    func respond(_ id: UUID, accept: Bool) {
        Store.shared.answerInvitation(id, accept: accept)
        enqueue(.respond(id: id.uuidString, accept: accept))
        kick()
    }

    // An invitation works for one person, so only one nobody got yet is shown again instead of making a new one.
    func createInvite(calling name: String) async throws -> (code: String, link: URL) {
        guard let session = Account.shared.session else { throw Backend.Failure.unauthorized }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        if let code = spare {
            spare = nil
            // Someone may have scanned it from the screen meanwhile.
            try? await loadFriends(token: session.token, account: session.userID)
            if state.invites.contains(where: { $0.code == code && $0.state == "open" && $0.expires > Date().addingTimeInterval(3600) }) {
                if trimmed.isEmpty {
                    spare = code
                } else {
                    setPendingName(code, trimmed)
                }
                return (code, Self.link(code))
            }
        }
        struct Created: Decodable {
            let code: String
            let expires: Int64
        }
        let created = try await Backend.request("POST", "/api/rema/invites", token: session.token, as: Created.self)
        guard state.account == nil || state.account == session.userID else { throw Backend.Failure.unauthorized }
        if trimmed.isEmpty {
            spare = created.code
        } else {
            state.pendingNames[created.code] = trimmed
        }
        state.invites.insert(SentInvite(code: created.code, state: "open", expires: Date(timeIntervalSince1970: Double(created.expires) / 1000)), at: 0)
        save()
        return (created.code, Self.link(created.code))
    }

    // Shared, copied or named: from now on the invitation belongs to one person.
    func handedOut(_ code: String) {
        if spare == code {
            spare = nil
        }
    }

    static func link(_ code: String) -> URL {
        URL(string: "https://remaapp.cc/i/\(code)")!
    }

    func setPendingName(_ code: String, _ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        state.pendingNames[code] = trimmed.isEmpty ? nil : trimmed
        if !trimmed.isEmpty {
            handedOut(code)
        }
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
        guard Account.shared.session?.userID == session.userID else { return }
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
        try await Backend.send("DELETE", "/api/rema/friends/\(Backend.segment(friendID))", token: session.token)
        state.names[friendID] = nil
        forget(friendID)
    }

    func block(_ userID: String, name: String = "") async throws {
        guard let session = Account.shared.session else { throw Backend.Failure.unauthorized }
        struct Body: Encodable { let user: String }
        let known = state.friends.first { $0.id == userID }?.name ?? name
        try await Backend.send("POST", "/api/rema/blocks", body: Body(user: userID), token: session.token)
        if !state.blocked.contains(where: { $0.id == userID }) {
            state.blocked.insert(SharedPerson(id: userID, name: known), at: 0)
        }
        // My name for the person stays, so the list of the blocked shows whom I meant.
        forget(userID)
    }

    // The person can invite me again; being friends takes a new invitation.
    func unblock(_ userID: String) async throws {
        guard let session = Account.shared.session else { throw Backend.Failure.unauthorized }
        try await Backend.send("DELETE", "/api/rema/blocks/\(Backend.segment(userID))", token: session.token)
        state.blocked.removeAll { $0.id == userID }
        save()
    }

    // The one who made a reminder adds friends to it or takes them out, and can ask again the ones who said no.
    func changeMembers(of id: UUID, to people: [SharedPerson]) {
        guard var local = Store.shared.reminder(id), var shared = local.shared, shared.isMine else { return }
        let wanted = Set(people.map(\.id))
        var members: [SharedMember] = shared.members.compactMap { member in
            let inside = member.status == SharedStatus.invited || member.status == SharedStatus.accepted
            guard wanted.contains(member.id) else {
                // Who said no or left stays listed as the server keeps them.
                return inside ? nil : member
            }
            var kept = member
            if !inside {
                kept.status = SharedStatus.invited
            }
            return kept
        }
        for person in people where !members.contains(where: { $0.id == person.id }) {
            members.append(SharedMember(id: person.id, name: person.name, status: SharedStatus.invited))
        }
        shared.members = members
        local.shared = shared
        Store.shared.save(local)
        let active = members.filter { $0.status == SharedStatus.invited || $0.status == SharedStatus.accepted }.map(\.id)
        enqueue(.update(id: local.id.uuidString, data: local.sharedData, members: active, stamp: Self.stamp()))
        kick()
    }

    // Without the friendship nothing is shared any more, here as on the server.
    private func forget(_ userID: String) {
        state.friends.removeAll { $0.id == userID }
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
        let trimmed = name.cleanedName()
        struct Body: Encodable { let name: String }
        try await Backend.send("PATCH", "/api/collections/users/records/\(Backend.segment(session.userID))", body: Body(name: trimmed), token: session.token)
        state.myName = trimmed
        save()
    }

    private func loadFriends(token: String, account: String) async throws {
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
        struct Blocks: Decodable { let blocked: [SharedPerson]? }
        let answer = try await Backend.request("GET", "/api/rema/friends", token: token, as: Answer.self)
        let blocks = try? await Backend.request("GET", "/api/rema/blocks", token: token, as: Blocks.self)
        guard state.account == account, Account.shared.session?.userID == account else { return }
        if let blocks {
            // The server keeps no name for someone blocked before ever being a friend; the one seen here stays.
            let known = Dictionary(state.blocked.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            state.blocked = (blocks.blocked ?? []).map { person in
                person.name.isEmpty ? SharedPerson(id: person.id, name: known[person.id] ?? "") : person
            }
        }
        state.friends = (answer.friends ?? []).map { Friend(id: $0.id, name: ($0.name ?? "").cleanedName(), since: Date(timeIntervalSince1970: Double($0.since ?? 0) / 1000)) }
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

private extension Backend.Failure {
    // The server looked at the change and will never take it; sending it again changes nothing.
    var isRefusal: Bool {
        switch self {
        case .invalid, .conflict:
            return true
        default:
            return false
        }
    }
}
