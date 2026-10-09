import SwiftUI

struct BellScreen: View {
    let onEvent: (BellService.Event) -> Void
    let onNews: (String) -> Void
    let onBack: () -> Void
    @State private var bell: BellService
    @State private var loading = true

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
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(read ? Palette.track : Palette.accent)
                Glyph(paths: icon(row), size: 18, lineWidth: 2, color: read ? Palette.text : Palette.onAccent)
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
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(read ? Text(verbatim: "") : Text("New"))
    }

    private func icon(_ row: BellService.Row) -> [String] {
        guard case .event(let event) = row else { return Icons.megaphone }
        switch event.kind {
        case "friend", "unfriended": return Icons.people
        case "accepted", "done", "ticked": return Icons.check
        case "declined", "left": return Icons.close
        case "deleted": return Icons.trash
        case "changed": return Icons.pen
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
        default: ""
        }
    }

    private func when(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.current.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
