import SwiftUI

struct NewsScreen: View {
    let onOpen: (String) -> Void
    let onBack: () -> Void
    @State private var news = NewsService.shared
    @State private var loading = true

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    if news.items.isEmpty {
                        Text(loading ? "Loading…" : "No news yet.")
                            .font(.app(.golos, 15))
                            .foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(news.items) { item in
                        Button {
                            onOpen(item.id)
                        } label: {
                            card(item)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .refreshable { await news.refresh(force: true) }
            .pinnedHeader {
                ScreenHeader(title: "News", leading: .back, action: onBack)
            }
        }
        .foregroundStyle(Palette.text)
        .task {
            await news.refresh(force: true)
            loading = false
        }
        // Marked as read on the way out, so «New» stays in sight while the list is open.
        .onDisappear { news.markSeen(news.items.map(\.id)) }
    }

    private func card(_ item: NewsService.Item) -> some View {
        let fresh = !news.seen.contains(item.id)
        let date = NewsDate.text(item.day)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if fresh {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 8, height: 8)
                }
                Text(verbatim: fresh ? String(localized: "New · \(date)", bundle: .app, locale: .app) : date)
                    .font(.app(.golos, 12, weight: 600))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(fresh ? Palette.accentText : Palette.secondary)
            }
            Text(verbatim: item.title)
                .font(.app(.golos, 17, weight: 600))
                .lineHeight(22, .golos, 17)
                .multilineTextAlignment(.leading)
            if !item.body.isEmpty {
                Text(verbatim: item.body)
                    .font(.app(.golos, 14))
                    .lineHeight(20, .golos, 14)
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }
}

struct NewsItemScreen: View {
    let id: String
    let onBack: () -> Void
    @State private var news = NewsService.shared
    @State private var loading = true
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                Group {
                    if let item = news.item(id) {
                        article(item)
                    } else {
                        Text(loading ? "Loading…" : "This news is no longer here.")
                            .font(.app(.golos, 15))
                            .foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "News", leading: .back, action: onBack)
            }
        }
        .foregroundStyle(Palette.text)
        .task {
            if news.item(id) == nil {
                await news.refresh(force: true)
            }
            loading = false
            news.markSeen([id])
        }
    }

    private func article(_ item: NewsService.Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: NewsDate.text(item.day))
                .font(.app(.golos, 12, weight: 600))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Palette.secondary)
            Text(verbatim: item.title)
                .font(.app(.jost, 28, weight: 500))
                .lineHeight(32, .jost, 28)
                .padding(.top, 8)
            if !item.body.isEmpty {
                Text(verbatim: item.body)
                    .font(.app(.golos, 16))
                    .lineHeight(24, .golos, 16)
                    .padding(.top, 16)
                    .textSelection(.enabled)
            }
            if let url = item.url {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 8) {
                        Text("More on the website")
                            .font(.app(.golos, 15, weight: 600))
                        Glyph(paths: Icons.external, size: 16, lineWidth: 2, color: Palette.text)
                    }
                    .foregroundStyle(Palette.text)
                }
                .buttonStyle(RaisedButtonStyle(height: 48, radius: 14))
                .padding(.top, 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 24)
        .panel(radius: 24)
    }
}

enum NewsDate {
    static func text(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(AppLanguage.current.locale))
    }
}

struct NewsConsentSheet: View {
    let onAnswer: (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .circular)
                        .fill(Palette.accent)
                    Glyph(paths: Icons.megaphone, size: 32, lineWidth: 2, color: Palette.onAccent)
                }
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
                .padding(.top, 28)
                Text("Rema news")
                    .font(.app(.jost, 26, weight: 500))
                    .padding(.top, 18)
                    .accessibilityAddTraits(.isHeader)
                Text("Sometimes we tell what is new in Rema and share tips. Send this news by push? No more than a couple of times a month and only in the daytime.")
                    .font(.app(.golos, 16))
                    .lineHeight(23, .golos, 16)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                Button("Send me news") { onAnswer(true) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 24)
                Button {
                    onAnswer(false)
                } label: {
                    Text("Not now")
                        .font(.app(.golos, 16, weight: 500))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 8)
                Text("You can turn this off in Settings.")
                    .font(.app(.golos, 13))
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(Palette.text)
    }
}

struct UpdateNotice: View {
    let version: String
    let onUpdate: () -> Void
    let onHide: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .circular)
                    .fill(Palette.segment)
                Glyph(paths: Icons.download, size: 20, lineWidth: 2.2, color: Palette.accentOnDark)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Rema \(version) is out")
                    .font(.app(.golos, 15, weight: 600))
                Text("Update to get what is new")
                    .font(.app(.golos, 13))
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Update", action: onUpdate)
                .buttonStyle(SmallButtonStyle(prominent: true))
            Button(action: onHide) {
                Glyph(paths: Icons.close, size: 14, lineWidth: 2.2, color: Palette.secondary)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(Text("Hide"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 14)
        .panel(radius: 20)
    }
}
