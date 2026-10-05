import SwiftUI

struct AccountScreen: View {
    struct Summary {
        var email: String
        var method: Account.Method
        var status: SyncService.Status
        var savedAt: Date?
        var reminders: Int
        var places: Int
    }

    let summary: Summary
    var locale: Locale = AppLanguage.current.locale
    var onSignOut: (_ discardingChanges: Bool) async -> Bool = { _ in true }
    var onDelete: () async throws -> Void = {}
    var onBack: () -> Void

    @State private var askDiscard = false
    @State private var askDelete = false
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    identity
                        .padding(.top, 16)
                    SectionLabel(text: "Sync")
                        .padding(.top, 16)
                    PanelList {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 10, height: 10)
                                .padding(.horizontal, 5)
                            Text(verbatim: statusText)
                                .font(.app(.golos, 16, weight: 500))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let time = statusTime {
                                Text(verbatim: time)
                                    .font(.app(.golos, 14))
                                    .foregroundStyle(Palette.secondary)
                            }
                        }
                        .frame(minHeight: 52)
                        Hairline()
                        countRow(icon: Icons.clock, title: "Reminders", count: summary.reminders)
                        Hairline()
                        countRow(icon: Icons.pin, title: "Places", count: summary.places)
                    }
                    .padding(.top, 6)
                    FormNote(text: "Sign in to this account on another phone and your reminders will appear there.")
                        .padding(.top, 10)
                    Button {
                        signOut(discarding: false)
                    } label: {
                        if busy {
                            ProgressView()
                        } else {
                            Text("Sign out")
                        }
                    }
                    .buttonStyle(RaisedButtonStyle())
                    .padding(.top, 22)
                    FormNote(text: "After you sign out, reminders disappear from this phone and come back the next time you sign in.")
                        .padding(.top, 8)
                    if let problem {
                        FormProblem(text: problem)
                            .padding(.top, 12)
                    }
                    Button {
                        askDelete = true
                    } label: {
                        Text("Delete account")
                            .font(.app(.golos, 15, weight: 600))
                            .foregroundStyle(Palette.urgentText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(RowPressStyle())
                    .padding(.top, 14)
                    Text("The account and all reminders will be deleted forever")
                        .font(.app(.golos, 12))
                        .lineHeight(16, .golos, 12)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "Account", leading: .back, action: onBack)
            }
        }
        .foregroundStyle(Palette.text)
        .disabled(busy)
        .alert("Some changes are not in the account yet", isPresented: $askDiscard) {
            Button("Sign out anyway", role: .destructive) { signOut(discarding: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("There is no connection right now. If you sign out, these changes will be lost.")
        }
        .alert("Delete the account?", isPresented: $askDelete) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The account and all reminders will be deleted forever. This cannot be undone.")
        }
    }

    private var identity: some View {
        HStack(spacing: 14) {
            ZStack {
                RaisedCircle(size: 52)
                Glyph(paths: Icons.person, size: 24, lineWidth: 1.9, color: Palette.text)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: summary.email.isEmpty ? String(localized: "Apple ID with a hidden email") : summary.email)
                    .font(.app(.golos, 17, weight: 600))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    switch summary.method {
                    case .apple:
                        AppleMark(color: Palette.secondary)
                            .frame(width: 11, height: 13)
                        Text("Signed in with Apple")
                    case .google:
                        GoogleMark()
                            .frame(width: 12, height: 12)
                        Text("Signed in with Google")
                    case .password:
                        Glyph(paths: Icons.envelope, size: 14, lineWidth: 2, color: Palette.secondary)
                        Text("Signed in with email")
                    }
                }
                .font(.app(.golos, 13))
                .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .panel()
    }

    private func countRow(icon: [String], title: LocalizedStringKey, count: Int) -> some View {
        HStack(spacing: 12) {
            Glyph(paths: icon, size: 20, lineWidth: 2, color: Palette.text)
            Text(title)
                .font(.app(.golos, 16, weight: 500))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "\(count)")
                .font(.app(.jost, 17, weight: 500))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(minHeight: 52)
    }

    private var statusColor: Color {
        switch summary.status {
        case .saved, .idle: Palette.yearly
        case .syncing: Palette.accent
        case .offline: Palette.faint
        case .failed: Palette.urgent
        }
    }

    private var statusText: String {
        switch summary.status {
        case .saved, .idle: String(localized: "Everything is saved in the account")
        case .syncing: String(localized: "Saving…")
        case .offline: String(localized: "No connection, changes will be saved later")
        case .failed: String(localized: "Not saved yet, trying again")
        }
    }

    private var statusTime: String? {
        guard summary.status == .saved || summary.status == .idle, let savedAt = summary.savedAt else { return nil }
        if Date().timeIntervalSince(savedAt) < 60 {
            return String(localized: "just now")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: savedAt, relativeTo: Date())
    }

    private func signOut(discarding: Bool) {
        busy = true
        problem = nil
        Task {
            let done = await onSignOut(discarding)
            busy = false
            if !done {
                askDiscard = true
            }
        }
    }

    private func delete() {
        busy = true
        problem = nil
        Task {
            do {
                try await onDelete()
            } catch let failure as Backend.Failure {
                problem = failure == .offline ? failure.message : String(localized: "Could not delete the account. Try again.")
            } catch {
                problem = String(localized: "Could not delete the account. Try again.")
            }
            busy = false
        }
    }
}
