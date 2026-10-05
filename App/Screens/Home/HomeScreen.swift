import SwiftUI

struct HomeScreen: View {
    let content: HomeContent
    var onToggle: (HomeContent.Row) -> Void = { _ in }
    var onOpen: (UUID) -> Void = { _ in }
    var onCompose: () -> Void = {}
    var onVoice: () -> Void = {}
    var onCalendar: () -> Void = {}
    @State private var addPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Dial(
                    nowHour: content.nowHour,
                    nowMinute: content.nowMinute,
                    markers: content.markers,
                    windowTime: content.next?.time ?? content.nowText,
                    windowCaption: content.next?.countdown ?? String(localized: "now")
                )
                .padding(.top, 14)
                if let next = content.next {
                    nextSummary(next)
                        .padding(.top, 10)
                        .onTapGesture { onOpen(next.reminderID) }
                }
                if content.rows.isEmpty {
                    emptyDay
                        .padding(.top, 12)
                } else {
                    list
                        .padding(.top, 12)
                }
                if !content.tiles.isEmpty {
                    tiles
                        .padding(.top, 12)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 15)

            composer
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: content.rows.map(\.id))
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: content.dateLine)
                    .font(.app(.golos, 12, weight: 600))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.secondary)
                Text("Today")
                    .font(.app(.jost, 32, weight: 500))
                    .frame(height: 36)
            }
            Spacer(minLength: 0)
            Button(action: onCalendar) {
                ZStack {
                    RaisedCircle()
                    Glyph(paths: Icons.calendar, size: 20, lineWidth: 1.8, color: Palette.text)
                }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(Text("Calendar"))
        }
    }

    private func nextSummary(_ next: HomeContent.Next) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: next.title)
                .font(.app(.golos, 17, weight: 600))
            if next.urgent || next.note != nil {
                HStack(spacing: 8) {
                    if next.urgent {
                        UrgentBadge()
                    }
                    if let note = next.note {
                        Text(verbatim: note)
                            .font(.app(.golos, 13))
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
        .contentShape(Rectangle())
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(content.rows) { row in
                HomeRow(row: row, onToggle: { onToggle(row) })
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen(row.reminderID) }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                if row.id != content.rows.last?.id {
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .panel()
    }

    private var emptyDay: some View {
        VStack(spacing: 6) {
            Text("Nothing for today")
                .font(.app(.golos, 16, weight: 600))
            Text("Write below what and when to remind you")
                .font(.app(.golos, 13))
                .foregroundStyle(Palette.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .panel()
    }

    private var tiles: some View {
        HStack(spacing: 10) {
            ForEach(content.tiles) { tile in
                HomeTile(tile: tile)
                    .onTapGesture { onOpen(tile.reminderID) }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            Button(action: onCompose) {
                Text("What and when to remind?")
                    .font(.app(.golos, 16))
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("New reminder"))
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .circular)
                    .fill(Palette.accent)
                    .insetShadow(RoundedRectangle(cornerRadius: 12, style: .circular), .black.opacity(0.14), y: -3)
                Glyph(paths: Icons.plus, size: 22, lineWidth: 2.4, color: Palette.onAccent)
            }
            .frame(width: 44, height: 44)
            .scaleEffect(addPressed ? 0.94 : 1)
            .animation(Motion.press, value: addPressed)
            .contentShape(Rectangle())
            .onTapGesture(perform: onCompose)
            .onLongPressGesture(minimumDuration: 0.35, perform: onVoice, onPressingChanged: { addPressed = $0 })
            .accessibilityElement()
            .accessibilityLabel(Text("Add reminder"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, onCompose)
            .accessibilityAction(named: Text("Dictate"), onVoice)
        }
        .padding(.leading, 18)
        .padding(.trailing, 7)
        .frame(height: 58)
        .inputBar()
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

private struct HomeRow: View {
    let row: HomeContent.Row
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(verbatim: row.time)
                .font(.app(.jost, 18, weight: row.highlighted ? 600 : 500))
                .monospacedDigit()
                .foregroundStyle(timeColor)
                .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title)
                    .font(.app(.golos, 16, weight: row.highlighted ? 600 : 400))
                    .strikethrough(row.done)
                    .foregroundStyle(row.done ? Palette.secondary : Palette.text)
                if let subtitle = row.subtitle {
                    Text(verbatim: subtitle)
                        .font(.app(.golos, 12))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onToggle) {
                CheckBox(isOn: row.done)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(.trailing, -9)
            .accessibilityLabel(Text(row.done ? LocalizedStringKey("Mark as not done") : LocalizedStringKey("Mark as done")))
        }
        .frame(minHeight: row.subtitle == nil ? 46 : 52)
    }

    private var timeColor: Color {
        if row.done { return Palette.secondary }
        if row.highlighted { return Palette.accentText }
        return Palette.text
    }
}

private struct HomeTile: View {
    let tile: HomeContent.Tile

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Glyph(paths: tile.icon == .place ? Icons.pin : Icons.star, size: 12, lineWidth: 2.4, color: Palette.secondary)
                Text(verbatim: tile.label)
                    .font(.app(.golos, 11, weight: 600))
                    .tracking(0.88)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.secondary)
            }
            Text(verbatim: tile.title)
                .font(.app(.golos, 15, weight: 600))
                .lineLimit(1)
            Text(verbatim: tile.subtitle)
                .font(.app(.golos, 12))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 80, alignment: .topLeading)
        .panel(radius: 18)
        .contentShape(Rectangle())
    }
}

#Preview {
    HomeScreen(content: SampleData.home)
}
