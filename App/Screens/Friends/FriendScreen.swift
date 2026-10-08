import RemaCore
import SwiftUI

struct FriendScreen: View {
    let store: Store
    let friendID: String
    var now: Date = Date()
    var calendar: Calendar = .current
    var locale: Locale = AppLanguage.current.locale
    let onOpen: (UUID) -> Void
    let onBack: () -> Void

    @State private var service = SharedService.shared
    @State private var name = ""
    @State private var confirming: Confirm?
    @State private var problem: String?
    @State private var reported = false
    @FocusState private var nameFocused: Bool

    enum Confirm: Identifiable {
        case remove
        case block
        case report

        var id: Self { self }
    }

    private var friend: SharedService.Friend? {
        service.state.friends.first { $0.id == friendID }
    }

    private var ownName: String {
        friend?.name ?? ""
    }

    private var shown: String {
        service.name(of: friendID, fallback: ownName)
    }

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    private var shared: [Reminder] {
        store.reminders.filter { reminder in
            guard let shared = reminder.shared, reminder.deletedAt == nil else { return false }
            return shared.owner.id == friendID || shared.members.contains { $0.id == friendID && ($0.status == SharedStatus.accepted || $0.status == SharedStatus.invited) }
        }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Avatar(name: shown, seed: friendID, size: 72)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                    SectionLabel(text: "What you call them")
                        .padding(.horizontal, 4)
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                    nameField
                    Note(verbatim: ownName.isEmpty ? String(localized: "Only you see this name, it never goes to your friend.", bundle: .app, locale: .app) : String(localized: "Only you see this name, it never goes to your friend. They call themselves “\(ownName)”.", bundle: .app, locale: .app))
                        .padding(.top, 10)
                    SectionLabel(text: "Shared reminders")
                        .padding(.horizontal, 4)
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                    if shared.isEmpty {
                        Text("Nothing shared yet")
                            .font(.app(.golos, 15, weight: 600))
                            .foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .panel()
                    } else {
                        PanelList {
                            ForEach(Array(shared.enumerated()), id: \.element.id) { index, reminder in
                                Button {
                                    onOpen(reminder.id)
                                } label: {
                                    sharedRow(reminder)
                                }
                                .buttonStyle(RowPressStyle())
                                if index < shared.count - 1 {
                                    Hairline()
                                }
                            }
                        }
                    }
                    PanelList {
                        ActionRow(icon: Icons.flag, title: Text(reported ? "Report sent" : "Report"), tint: Palette.urgentIcon) {
                            guard !reported else { return }
                            confirming = .report
                        }
                        Hairline()
                        ActionRow(icon: Icons.exit, title: Text("Remove from friends"), tint: Palette.urgentIcon) {
                            confirming = .remove
                        }
                        Hairline()
                        ActionRow(icon: Icons.block, title: Text(verbatim: String(localized: "Block \(shown)", bundle: .app, locale: .app)), tint: Palette.urgentIcon) {
                            confirming = .block
                        }
                    }
                    .padding(.top, 14)
                    Note("Blocking removes the friendship and the shared reminders with this person at once and forbids new invitations.")
                        .padding(.top, 10)
                    if let problem {
                        Note(verbatim: problem)
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .pinnedHeader {
                ScreenHeader(title: LocalizedStringKey(shown), leading: .back, action: onBack)
            }
        }
        .foregroundStyle(Palette.text)
        .onAppear { name = service.state.names[friendID] ?? "" }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible) {
            switch confirming {
            case .remove:
                Button("Remove from friends", role: .destructive) { act { try await service.remove(friendID) } }
            case .block:
                Button(String(localized: "Block \(shown)", bundle: .app, locale: .app), role: .destructive) { act { try await service.block(friendID) } }
            case .report:
                Button("Report", role: .destructive) { report() }
            case nil:
                EmptyView()
            }
        }
    }

    private var confirmTitle: String {
        switch confirming {
        case .remove: String(localized: "Remove \(shown) from friends? Your shared reminders with them go away.", bundle: .app, locale: .app)
        case .block: String(localized: "Block \(shown)? They will not be able to invite you again.", bundle: .app, locale: .app)
        case .report: String(localized: "Report \(shown)? Rema will look into it within a day.", bundle: .app, locale: .app)
        case nil: ""
        }
    }

    private var nameField: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .circular)
        return TextField(text: $name, prompt: Text(verbatim: ownName.isEmpty ? String(localized: "Name", bundle: .app, locale: .app) : ownName).foregroundColor(Palette.secondary)) {
            Text("What you call them")
        }
        .font(.app(.golos, 17))
        .tint(Palette.accent)
        .focused($nameFocused)
        .submitLabel(.done)
        .onChange(of: name) { _, value in service.rename(friendID, to: value) }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background {
            shape
                .fill(Palette.well)
                .insetShadow(shape, Palette.wellShadow, blur: 3, y: 1)
        }
        .overlay(shape.strokeBorder(Palette.wellBorder, lineWidth: 1))
    }

    private func sharedRow(_ reminder: Reminder) -> some View {
        let next = reminder.schedule.flatMap { Recurrence.next($0, after: now.addingTimeInterval(-60), limit: 1, calendar: calendar).first }
        let mine = reminder.shared?.isMine == true
        let subtitle = [next.map { describer.dayAndTime($0, now: now) }, mine ? String(localized: "made by you", bundle: .app, locale: .app) : String(localized: "made by \(shown)", bundle: .app, locale: .app)].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 14) {
            Text(verbatim: next.map(describer.time) ?? "")
                .font(.app(.jost, 18, weight: 500))
                .monospacedDigit()
                .timeColumn()
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: reminder.title)
                    .font(.app(.golos, 16))
                    .lineLimit(2)
                Text(verbatim: subtitle)
                    .font(.app(.golos, 12))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    private func act(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                Feedback.play(.delete)
                onBack()
            } catch let failure as Backend.Failure {
                problem = failure.message
            } catch {
                problem = Backend.Failure.server.message
            }
        }
    }

    private func report() {
        Task {
            do {
                try await service.report(user: friendID, shared: nil, reason: "user")
                withAnimation(Motion.standard) { reported = true }
            } catch let failure as Backend.Failure {
                problem = failure.message
            } catch {
                problem = Backend.Failure.server.message
            }
        }
    }
}
