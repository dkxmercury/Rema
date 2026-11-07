import SwiftUI

struct BellScreen: View {
    let onEvent: (BellService.Event) -> Void
    let onNews: (String) -> Void
    let onBack: () -> Void
    @State private var bell: BellService
    @State private var loading = true
    @State private var thanked = Set(UserDefaults.standard.stringArray(forKey: BellScreen.thankedKey) ?? [])
    private static let thankedKey = "bell.thanked"

    init(bell: BellService = .shared, onEvent: @escaping (BellService.Event) -> Void, onNews: @escaping (String) -> Void, onBack: @escaping () -> Void) {
        _bell = State(initialValue: bell)
        self.onEvent = onEvent
        self.onNews = onNews
        self.onBack = onBack
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if bell.unread > 0 {
                        HStack {
                            Spacer()
                            Button("Read all") {
                                withAnimation(Motion.small) { bell.markAllRead() }
                            }
                            .buttonStyle(SmallButtonStyle(prominent: false))
                        }
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    let rows = bell.rows
                    if rows.isEmpty {
                        Text(loading ? "Loading…" : "Nothing here yet.")
                            .font(.app(.golos, 15))
                            .foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        PanelList {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 {
                                    Hairline()
                                }
                                Button {
                                    bell.markRead(row)
                                    switch row {
                                    case .event(let event): onEvent(event)
                                    case .news(let item): onNews(item.id)
                                    }
                                } label: {
                                    line(row)
                                }
                                .buttonStyle(RowPressStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 40)
                .animation(Motion.standard, value: bell.rows.map(\.id))
            }
            .scrollIndicators(.hidden)
            .refreshable { await bell.refresh(force: true) }
            .pinnedHeader {
                ScreenHeader(title: "Notifications", leading: .back, action: onBack)
            }
        }
        .foregroundStyle(Palette.text)
        .task {
            await bell.refresh(force: true)
            loading = false
        }
    }

    private func line(_ row: BellService.Row) -> some View {
        let read = bell.isRead(row)
        let glyph = icon(row)
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(read ? Palette.track : Palette.accent)
                Glyph(paths: glyph, size: 18, lineWidth: 2, color: read ? Palette.text : Palette.onAccent, filled: glyph == Icons.heart)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: heading(row))
                        .font(.app(.golos, 16, weight: read ? 500 : 600))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: when(row.day))
                        .font(.app(.golos, 12))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                Text(verbatim: detail(row))
                    .font(.app(.golos, 14))
                    .lineHeight(19, .golos, 14)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if case .event(let event) = row, Self.thankable(event) {
                    thanks(event)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(read ? Text(verbatim: "") : Text("New"))
        .accessibilityActions {
            if case .event(let event) = row, Self.thankable(event), !thanked.contains(event.id) {
                Button("Thank you") { thank(event) }
            }
        }
    }

    // A friend's tick can be answered with a thank-you, once; the server keeps it to one per tick too.
    static func thankable(_ event: BellService.Event) -> Bool {
        (event.kind == "ticked" || event.kind == "done") && UUID(uuidString: event.item) != nil && event.actor != SharedNames.me
    }

    @ViewBuilder
    private func thanks(_ event: BellService.Event) -> some View {
        if thanked.contains(event.id) {
            HStack(spacing: 6) {
                Glyph(paths: Icons.check, size: 15, lineWidth: 2.6, color: Palette.secondary)
                Text("Thanks sent")
                    .font(.app(.golos, 14, weight: 600))
                    .foregroundStyle(Palette.secondary)
            }
            .frame(height: 32)
        } else {
            Button {
                thank(event)
            } label: {
                HStack(spacing: 6) {
                    Glyph(paths: Icons.heart, size: 15, lineWidth: 2.2, color: Palette.accent, filled: true)
                    Text("Thank you")
                }
                .padding(.horizontal, 6)
            }
            .buttonStyle(SmallButtonStyle(prominent: false, height: 36))
            .fixedSize()
        }
    }

    private func thank(_ event: BellService.Event) {
        guard let id = UUID(uuidString: event.item) else { return }
        Task {
            do {
                try await SharedService.shared.thank(event.actor, in: id)
                Feedback.play(.save)
                withAnimation(Motion.standard) { thanked.insert(event.id) }
                UserDefaults.standard.set(Array(thanked), forKey: Self.thankedKey)
            } catch {
                Feedback.play(.error)
            }
        }
    }

    private func icon(_ row: BellService.Row) -> [String] {
        guard case .event(let event) = row else { return Icons.megaphone }
        switch event.kind {
        case "friend", "unfriended": return Icons.people
        case "accepted", "done", "ticked": return Icons.check
        case "declined", "left": return Icons.close
        case "deleted": return Icons.trash
        case "changed": return Icons.pen
        case "comment": return Icons.speech
        case "thanks": return Icons.heart
        default: return Icons.bell
        }
    }

    private func heading(_ row: BellService.Row) -> String {
        switch row {
        case .event(let event): SharedService.shared.name(of: event.actor, fallback: event.actorName)
        case .news(let item): item.title
        }
    }

    private func detail(_ row: BellService.Row) -> String {
        switch row {
        case .news(let item):
            return item.body
        case .event(let event):
            if event.kind == "comment", let text = event.text, !text.isEmpty {
                return event.title.isEmpty ? text : "\(String(localized: "Writes in \(event.title.quoted())", bundle: .app, locale: .app)) · \(text)"
            }
            let what = Self.text(event.kind)
            return event.title.isEmpty ? what : "\(what) · \(event.title)"
        }
    }

    static func text(_ kind: String) -> String {
        switch kind {
        case "new": String(localized: "Invitation to a shared reminder", bundle: .app, locale: .app)
        case "changed": String(localized: "Changed", bundle: .app, locale: .app)
        case "deleted": String(localized: "Deleted for everyone", bundle: .app, locale: .app)
        case "accepted": String(localized: "Accepted the invitation", bundle: .app, locale: .app)
        case "declined": String(localized: "Declined the invitation", bundle: .app, locale: .app)
        case "left": String(localized: "No longer in this reminder", bundle: .app, locale: .app)
        case "done": String(localized: "Done, ticked for everybody", bundle: .app, locale: .app)
        case "ticked": String(localized: "Marked as done", bundle: .app, locale: .app)
        case "friend": String(localized: "You are friends in Rema now", bundle: .app, locale: .app)
        case "unfriended": String(localized: "No longer friends in Rema", bundle: .app, locale: .app)
        case "comment": String(localized: "New message", bundle: .app, locale: .app)
        case "thanks": String(localized: "Says thank you", bundle: .app, locale: .app)
        default: ""
        }
    }

    private func when(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.current.locale
        formatter.unitsStyle = .short
        let now = Date()
        guard now.timeIntervalSince(date) >= 86_400 else {
            return formatter.localizedString(for: date, relativeTo: now)
        }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 {
            formatter.dateTimeStyle = .named
            return formatter.localizedString(from: DateComponents(day: -1))
        }
        if days > 1, days < 7 {
            return formatter.localizedString(from: DateComponents(day: -days))
        }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
