import RemaCore
import SwiftUI
import UIKit

@MainActor
@Observable
final class DiscussionModel {
    let reminderID: UUID
    private(set) var comments: [SharedComment]
    private(set) var sending = false
    private(set) var failed = false
    @ObservationIgnored private var cursor: Int64 = 0
    @ObservationIgnored private var loading = false

    init(reminderID: UUID, comments: [SharedComment] = []) {
        self.reminderID = reminderID
        self.comments = comments
    }

    func refresh() async {
        guard !loading, Account.shared.session != nil else { return }
        loading = true
        defer { loading = false }
        do {
            for _ in 0..<10 {
                let page = try await SharedService.shared.comments(of: reminderID, since: cursor)
                comments = Discussion.merge(page.items ?? [], into: comments)
                cursor = max(cursor, page.cursor ?? cursor)
                if page.more != true {
                    break
                }
            }
            failed = false
        } catch {
            failed = true
        }
    }

    func send(_ text: String) async -> Bool {
        guard let words = Discussion.cleaned(text), !sending else { return false }
        sending = true
        defer { sending = false }
        do {
            let comment = try await SharedService.shared.sendComment(words, id: UUID().uuidString, to: reminderID)
            comments = Discussion.merge([comment], into: comments)
            failed = false
            return true
        } catch {
            failed = true
            return false
        }
    }

    func takeBack(_ comment: SharedComment) async {
        do {
            try await SharedService.shared.deleteComment(comment.id, in: reminderID)
            await refresh()
        } catch {
            failed = true
        }
    }
}

struct DiscussionSection: View {
    let model: DiscussionModel
    let me: String
    let name: (String) -> String
    var locale: Locale = AppLanguage.current.locale
    let onReport: (SharedComment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Discussion")
                .padding(.horizontal, 4)
            if model.comments.isEmpty {
                Text("No messages yet. Write to everyone in the reminder")
                    .font(.app(.golos, 14))
                    .foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 4)
            }
            ForEach(model.comments) { comment in
                bubble(comment)
            }
            Text("Everyone in the reminder sees the messages. Press and hold a message to report it")
                .font(.app(.golos, 12))
                .lineHeight(17, .golos, 12)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
        }
    }

    private func bubble(_ comment: SharedComment) -> some View {
        let mine = comment.author == me
        let words = comment.deleted ? String(localized: "Message deleted", bundle: .app, locale: .app) : comment.text ?? ""
        let shape = UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: mine ? 16 : 4, bottomTrailingRadius: mine ? 4 : 16, topTrailingRadius: 16, style: .circular)
        let author = name(comment.author)
        return HStack(alignment: .bottom, spacing: 8) {
            if !mine {
                Avatar(name: author.isEmpty ? "?" : author, seed: comment.author, size: 28)
            }
            message(comment, mine: mine, words: words, author: author, shape: shape)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .padding(mine ? .leading : .trailing, 48)
        .accessibilityElement(children: .combine)
    }

    private func message(_ comment: SharedComment, mine: Bool, words: String, author: String, shape: UnevenRoundedRectangle) -> some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            VStack(alignment: .leading, spacing: 1) {
                if !mine {
                    Text(verbatim: author)
                        .font(.app(.golos, 12, weight: 600))
                        .foregroundStyle(Palette.secondary)
                }
                Text(verbatim: words)
                    .font(.app(.golos, 15))
                    .italic(comment.deleted)
                    .foregroundStyle(comment.deleted ? Palette.secondary : (mine ? Palette.onSegment : Palette.text))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(shape.fill(mine && !comment.deleted ? Palette.segment : Palette.panel))
            .contextMenu {
                if !comment.deleted {
                    Button {
                        UIPasteboard.general.string = comment.text
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    if mine {
                        Button(role: .destructive) {
                            Task { await model.takeBack(comment) }
                        } label: {
                            Label("Delete for everyone", systemImage: "trash")
                        }
                    } else {
                        Button(role: .destructive) {
                            onReport(comment)
                        } label: {
                            Label("Report", systemImage: "flag")
                        }
                    }
                }
            }
            Text(verbatim: comment.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)))
                .font(.app(.golos, 11))
                .foregroundStyle(Palette.secondary)
        }
    }
}

struct CommentComposer: View {
    let model: DiscussionModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var ready: Bool {
        Discussion.cleaned(draft) != nil && !model.sending
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Write to everyone in it", text: $draft, axis: .vertical)
                .font(.app(.golos, 16))
                .lineLimit(1...4)
                .focused($focused)
                .padding(.vertical, 12)
            Button(action: send) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .circular)
                        .fill(Palette.accent)
                        .insetShadow(RoundedRectangle(cornerRadius: 12, style: .circular), .black.opacity(0.14), y: -3)
                    Glyph(paths: Icons.send, size: 20, lineWidth: 2.4, color: Palette.onAccent)
                }
                .frame(width: 44, height: 44)
                .opacity(ready ? 1 : 0.45)
            }
            .buttonStyle(PressableStyle())
            .disabled(!ready)
            .padding(.bottom, 7)
            .accessibilityLabel(Text("Send"))
        }
        .padding(.leading, 18)
        .padding(.trailing, 7)
        .inputBar()
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func send() {
        let text = draft
        Task {
            if await model.send(text) {
                Feedback.play(.save)
                draft = ""
            } else {
                Feedback.play(.error)
            }
        }
    }
}
