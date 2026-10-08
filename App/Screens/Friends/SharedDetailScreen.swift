import RemaCore
import SwiftUI

struct SharedDetailScreen: View {
    let store: Store
    let reminderID: UUID
    var now: Date = Date()
    var calendar: Calendar = .current
    var locale: Locale = AppLanguage.current.locale
    let onEdit: () -> Void
    let onClose: () -> Void

    @State private var service = SharedService.shared
    @State private var confirming: Confirm?
    @State private var problem: String?
    @State private var reported = false

    enum Confirm: Identifiable {
        case leave
        case delete
        case block
        case report

        var id: Self { self }
    }

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if let reminder = store.reminder(reminderID), let shared = reminder.shared {
                content(reminder, shared)
            }
        }
        .foregroundStyle(Palette.text)
        .onChange(of: store.reminder(reminderID) == nil) { _, gone in
            if gone {
                onClose()
            }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible) {
            switch confirming {
            case .leave:
                Button("Leave the reminder", role: .destructive) { remove() }
            case .delete:
                Button("Delete for everyone", role: .destructive) { remove() }
            case .block:
                Button(String(localized: "Block \(ownerName)", bundle: .app, locale: .app), role: .destructive) { block() }
            case .report:
                Button("Report", role: .destructive) { report() }
            case nil:
                EmptyView()
            }
        }
    }

    private var ownerName: String {
        guard let shared = store.reminder(reminderID)?.shared else { return "" }
        return service.name(of: shared.owner.id, fallback: shared.owner.name)
    }

    private var confirmTitle: String {
        switch confirming {
        case .leave: String(localized: "Leave the reminder? It goes from your phone, the others keep it.", bundle: .app, locale: .app)
        case .delete: String(localized: "Delete the reminder for everyone in it?", bundle: .app, locale: .app)
        case .block: String(localized: "Block \(ownerName)? The friendship and the shared reminders with them go away.", bundle: .app, locale: .app)
        case .report: String(localized: "Report this reminder? Rema will look into it within a day.", bundle: .app, locale: .app)
        case nil: ""
        }
    }

    private func content(_ reminder: Reminder, _ shared: SharedInfo) -> some View {
        let next = reminder.schedule.flatMap { Recurrence.next($0, after: now.addingTimeInterval(-60), limit: 1, calendar: calendar).first }
        let me = Account.shared.session?.userID
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: reminder.title)
                    .font(.app(.golos, 28, weight: 600))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: next.map(describer.time) ?? "—")
                        .font(.app(.jost, 44, weight: 500))
                        .monospacedDigit()
                    if let next {
                        Text(verbatim: describer.dayTitle(next))
                            .font(.app(.golos, 15, weight: 600))
                    }
                    Text(verbatim: shared.isMine ? String(localized: "made by you · only you can change it", bundle: .app, locale: .app) : String(localized: "made by \(ownerName) · only they can change it", bundle: .app, locale: .app))
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel()
                .padding(.top, 14)
                if shared.pending {
                    Note("Not sent yet. It goes to the friends when there is a connection.")
                        .padding(.top, 10)
                }
                SectionLabel(text: "Participants")
                    .padding(.horizontal, 4)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                PanelList {
                    participant(id: shared.owner.id, name: shared.isMine ? String(localized: "You", bundle: .app, locale: .app) : ownerName, status: String(localized: "author", bundle: .app, locale: .app), done: true)
                    ForEach(shared.members.filter { $0.status != "removed" }, id: \.id) { member in
                        Hairline()
                        participant(
                            id: member.id,
                            name: member.id == me ? String(localized: "You", bundle: .app, locale: .app) : service.name(of: member.id, fallback: member.name),
                            status: statusText(member.status),
                            done: member.status == SharedStatus.accepted
                        )
                    }
                }
                if shared.doneMode == .one {
                    Note("One “done” counts for everybody.")
                        .padding(.top, 10)
                }
                PanelList {
                    if shared.isMine {
                        ActionRow(icon: Icons.pen, title: Text("Change")) { onEdit() }
                        Hairline()
                        ActionRow(icon: Icons.trash, title: Text("Delete for everyone"), tint: Palette.urgentIcon) { confirming = .delete }
                    } else {
                        ActionRow(icon: Icons.exit, title: Text("Leave the reminder")) { confirming = .leave }
                        Hairline()
                        ActionRow(icon: Icons.flag, title: Text(reported ? "Report sent" : "Report"), tint: Palette.urgentIcon) {
                            guard !reported else { return }
                            confirming = .report
                        }
                        Hairline()
                        ActionRow(icon: Icons.block, title: Text(verbatim: String(localized: "Block \(ownerName)", bundle: .app, locale: .app)), tint: Palette.urgentIcon) { confirming = .block }
                    }
                }
                .padding(.top, 14)
                if !shared.isMine {
                    Note("Blocking removes the friendship and the shared reminders with this person at once and forbids new invitations.")
                        .padding(.top, 10)
                }
                if let problem {
                    Note(verbatim: problem)
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, shared.isInvitation ? 160 : 40)
        }
        .scrollIndicators(.hidden)
        .pinnedHeader {
            ScreenHeader(title: "Shared reminder", leading: .close, action: onClose)
        }
        .overlay(alignment: .bottom) {
            if shared.isInvitation {
                VStack(spacing: 6) {
                    Button {
                        Feedback.play(.save)
                        service.respond(reminderID, accept: true)
                    } label: {
                        Text("Accept")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button {
                        Feedback.play(.select)
                        service.respond(reminderID, accept: false)
                        onClose()
                    } label: {
                        Text("Decline")
                            .font(.app(.golos, 16, weight: 600))
                            .frame(height: 48)
                    }
                    .buttonStyle(RowPressStyle())
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
                .background(Palette.background.opacity(0.95))
            }
        }
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case SharedStatus.accepted: String(localized: "accepted", bundle: .app, locale: .app)
        case SharedStatus.declined: String(localized: "declined", bundle: .app, locale: .app)
        case SharedStatus.left: String(localized: "left", bundle: .app, locale: .app)
        default: String(localized: "invited", bundle: .app, locale: .app)
        }
    }

    private func participant(id: String, name: String, status: String, done: Bool) -> some View {
        FriendRow(name: name, seed: id, info: status) {
            if done {
                Glyph(paths: Icons.check, size: 18, lineWidth: 2.6, color: Palette.accent)
            }
        }
    }

    private func remove() {
        Feedback.play(.delete)
        store.delete(reminderID)
        onClose()
    }

    private func block() {
        guard let owner = store.reminder(reminderID)?.shared?.owner.id else { return }
        Task {
            do {
                try await service.block(owner)
                onClose()
            } catch let failure as Backend.Failure {
                problem = failure.friendsMessage
            } catch {
                problem = Backend.Failure.server.message
            }
        }
    }

    private func report() {
        let owner = store.reminder(reminderID)?.shared?.owner.id
        Task {
            do {
                try await service.report(user: owner, shared: reminderID, reason: "reminder")
                withAnimation(Motion.standard) { reported = true }
            } catch let failure as Backend.Failure {
                problem = failure.friendsMessage
            } catch {
                problem = Backend.Failure.server.message
            }
        }
    }
}
