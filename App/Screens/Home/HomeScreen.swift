import RemaCore
import SwiftUI

struct HomeScreen: View {
    let content: HomeContent
    var onToggle: (HomeContent.Row) -> Void = { _ in }
    var onOpen: (UUID) -> Void = { _ in }
    var onCompose: () -> Void = {}
    var onVoice: () -> Void = {}
    var onCalendar: () -> Void = {}
    var onSettings: () -> Void = {}
    var zoom: Namespace.ID?
    var onDelete: (UUID) -> Void = { _ in }
    var onMove: (UUID, Date) -> (() -> Void)? = { _, _ in nil }
    @State private var addPressed = false
    @State private var intro = false
    @State private var lift: DialLift?
    @State private var moved: Moved?
    @GestureState private var holding = false
    @Environment(\.introAnimations) private var introAnimations
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Dial(
                    handMinutes: shown ? Double(content.nowHour * 60 + content.nowMinute) : 0,
                    markerProgress: shown ? 1 : 0,
                    markers: content.markers,
                    windowTime: lift.map { clockText($0.minutes) } ?? content.next?.time ?? content.nowText,
                    windowCaption: lift.map { String(localized: "was \(clockText($0.original))") } ?? content.next?.countdown ?? String(localized: "now"),
                    lift: lift
                )
                .overlay { handles }
                .padding(.top, 14)
                if let lift, let row = content.rows.first(where: { lift.holds($0) }) {
                    liftSummary(row.title)
                        .padding(.top, 10)
                } else if let next = content.next {
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

            if let moved {
                MovedToast(text: String(localized: "Moved to \(moved.time)")) {
                    moved.undo()
                    withAnimation(Motion.standard) { self.moved = nil }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 98)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(.container, edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: moved.id) {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    withAnimation(Motion.standard) { self.moved = nil }
                }
            }

            composer
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: content.rows.map(\.id))
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: lift == nil)
        .onChange(of: holding) { _, active in
            guard !active else { return }
            // A cancelled gesture never reaches onEnded, so a lift left over after it is dropped here.
            DispatchQueue.main.async {
                if lift != nil {
                    withAnimation(Motion.standard) { lift = nil }
                }
            }
        }
        .onAppear {
            guard !intro else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { intro = true }
        }
    }

    private struct Moved: Identifiable {
        let id = UUID()
        let time: String
        let undo: () -> Void
    }

    private var earliestMove: Int {
        (content.nowHour * 60 + content.nowMinute) / 5 * 5 + 5
    }

    private func clockText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private var handles: some View {
        let geometry = DialGeometry()
        let unit = 236.0 / 280
        return ZStack(alignment: .topLeading) {
            if earliestMove < 24 * 60 {
                ForEach(content.markers.filter(\.movable), id: \.handleID) { marker in
                    let point = geometry.point(angle: geometry.angle(hour: marker.hour, minute: marker.minute), radius: 133)
                    Color.clear
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .gesture(moveGesture(marker, corner: CGPoint(x: point.x * unit - 22, y: point.y * unit - 22)))
                        .position(x: point.x * unit, y: point.y * unit)
                }
            }
        }
        .frame(width: 236, height: 236)
        .accessibilityHidden(true)
    }

    private func moveGesture(_ marker: DialMarker, corner: CGPoint) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($holding) { value, state, _ in
                if case .second(true, _) = value {
                    state = true
                }
            }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if lift == nil {
                    begin(marker)
                }
                if let drag {
                    follow(CGPoint(x: corner.x + drag.location.x, y: corner.y + drag.location.y))
                }
            }
            .onEnded { _ in
                finish()
            }
    }

    private func begin(_ marker: DialMarker) {
        guard let reminderID = marker.reminderID, let occurrence = marker.occurrence else { return }
        let start = marker.hour * 60 + marker.minute
        Feedback.play(.toggle)
        withAnimation(Motion.adaptive(Motion.small, reduceMotion: reduceMotion)) {
            lift = DialLift(reminderID: reminderID, occurrence: occurrence, original: start, minutes: start)
        }
    }

    private func follow(_ location: CGPoint) {
        guard var current = lift else { return }
        let dx = location.x - 118
        let dy = location.y - 118
        guard dx * dx + dy * dy > 30 * 30 else { return }
        var degrees = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 {
            degrees += 360
        }
        let raw = Int((degrees / 360 * 1440 / 5).rounded()) * 5 % 1440
        let target = allowed(raw)
        guard target != current.minutes else { return }
        current.minutes = target
        lift = current
        Feedback.play(.select)
    }

    // Only later today; a finger in the past snaps to whichever end of the free part is closer on the circle.
    private func allowed(_ minutes: Int) -> Int {
        let low = earliestMove
        let high = 24 * 60 - 5
        guard minutes < low || minutes > high else { return minutes }
        let toLow = (low - minutes + 1440) % 1440
        let toHigh = (minutes - high + 1440) % 1440
        return toLow <= toHigh ? low : high
    }

    private func finish() {
        guard let result = lift else { return }
        withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) {
            lift = nil
        }
        guard result.minutes != result.original,
              let date = Calendar.current.date(bySettingHour: result.minutes / 60, minute: result.minutes % 60, second: 0, of: result.occurrence),
              let undo = onMove(result.reminderID, date)
        else { return }
        Feedback.play(.save)
        withAnimation(Motion.standard) {
            moved = Moved(time: clockText(result.minutes), undo: undo)
        }
    }

    private func liftSummary(_ title: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: title)
                .font(.app(.golos, 17, weight: 600))
            Text("move around the dial in 5-minute steps · let go to reschedule")
                .font(.app(.golos, 13))
                .foregroundStyle(Palette.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private func movingRow(_ row: HomeContent.Row, _ lift: DialLift) -> HomeContent.Row {
        let was = String(localized: "was \(clockText(lift.original))")
        return HomeContent.Row(
            id: row.id,
            reminderID: row.reminderID,
            occurrence: row.occurrence,
            time: clockText(lift.minutes),
            title: row.title,
            subtitle: [was, row.subtitle].compactMap { $0 }.joined(separator: " · "),
            done: row.done,
            highlighted: true
        )
    }

    private var shown: Bool {
        intro || !introAnimations || reduceMotion
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
            Button(action: onSettings) {
                ZStack {
                    RaisedCircle()
                    Glyph(paths: Icons.sliders, size: 20, lineWidth: 1.8, color: Palette.text)
                }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(Text("Settings"))
            .padding(.trailing, -4)
            Button(action: onCalendar) {
                ZStack {
                    RaisedCircle()
                    Glyph(paths: Icons.calendar, size: 20, lineWidth: 1.8, color: Palette.text)
                }
            }
            .buttonStyle(PressableStyle())
            .zoomSource("calendar", in: zoom)
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
                let moving = lift.map { $0.holds(row) } ?? false
                AgendaRow(row: lift.map { moving ? movingRow(row, $0) : row } ?? row, onToggle: { onToggle(row) }, onDelete: { onDelete(row.reminderID) })
                    .background {
                        if moving {
                            Palette.accent.opacity(0.09)
                                .padding(.horizontal, -16)
                        }
                    }
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

private struct MovedToast: View {
    let text: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Glyph(paths: Icons.check, size: 18, lineWidth: 2.2, color: Palette.accentOnDark)
            Text(verbatim: text)
                .font(.app(.golos, 15, weight: 500))
                .foregroundStyle(Palette.dialWindowText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.app(.golos, 15, weight: 600))
                    .foregroundStyle(Palette.accentOnDark)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(height: 50)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .circular)
                .fill(Palette.dialWindow.shadow(.drop(color: .black.opacity(0.22), radius: 12, y: 10)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .circular)
                .strokeBorder(Palette.dialWindowBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private extension DialMarker {
    var handleID: String {
        "\(reminderID?.uuidString ?? "")-\(occurrence?.timeIntervalSince1970 ?? 0)"
    }
}

private extension DialLift {
    func holds(_ row: HomeContent.Row) -> Bool {
        row.reminderID == reminderID && row.occurrence == occurrence
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(Motion.press, value: configuration.isPressed)
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
