import RemaCore
import SwiftUI

struct HomeScreen: View {
    enum Postpone {
        case hour
        case morning
        case custom
    }

    let content: HomeContent
    var onToggle: (HomeContent.Row) -> Void = { _ in }
    var onOpen: (UUID) -> Void = { _ in }
    var onCompose: () -> Void = {}
    var onVoice: () -> Void = {}
    var onCalendar: () -> Void = {}
    var onSettings: () -> Void = {}
    var scheduledCount = 0
    var onScheduled: () -> Void = {}
    var zoom: Namespace.ID?
    var onDelete: (UUID) -> (() -> Void)? = { _ in nil }
    var onMove: (UUID, Date) -> (() -> Void)? = { _, _ in nil }
    var habit: HabitSuggestion?
    var onHabit: (HabitSuggestion, Bool) -> Void = { _, _ in }
    var onPostpone: (HomeContent.Row, Postpone) -> Void = { _, _ in }
    var tip: Tip?
    var onTip: (Tip, Bool) -> Void = { _, _ in }
    var loadingAccount = false
    var alert: HomeAlert?
    var onAlert: (HomeAlert) -> Void = { _ in }
    var snoozeHint: SnoozeHint?
    var onSnoozeHint: (SnoozeHint, Bool) -> Void = { _, _ in }
    var onRemindEvent: (HomeContent.Event) -> Void = { _ in }
    @State private var addPressed = false
    @State private var intro = false
    @State private var lift: DialLift?
    @State private var toast: Toast?
    @State private var postponing: HomeContent.Row?
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
                    windowCaption: lift.map { String(localized: "was \(clockText($0.original))", bundle: .app, locale: .app) } ?? content.next?.countdown ?? String(localized: "now", bundle: .app, locale: .app),
                    lift: lift,
                    badge: content.missedCount > 0 && lift == nil ? String(localized: "\(content.missedCount) missed", bundle: .app, locale: .app) : nil
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
                if scheduledCount > 0, lift == nil {
                    scheduledButton
                        .padding(.top, 12)
                }
                if let habit, lift == nil {
                    HabitSuggestionCard(suggestion: habit) { accepted in
                        withAnimation(Motion.standard) { onHabit(habit, accepted) }
                    }
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if let snoozeHint, lift == nil {
                    SnoozeHintCard(hint: snoozeHint) { accepted in
                        withAnimation(Motion.standard) { onSnoozeHint(snoozeHint, accepted) }
                    }
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                // A long day scrolls on its own while the dial and its handles stay in place.
                ViewThatFits(in: .vertical) {
                    day
                    ScrollView {
                        day
                            .padding(.horizontal, 18)
                            .padding(.top, 4)
                            .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .mask {
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                                .frame(height: 28)
                        }
                    }
                    .padding(.horizontal, -18)
                }
                .padding(.top, 12)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 15)
            .padding(.bottom, 92)

            if let tip, toast == nil, lift == nil {
                if tip == .voice {
                    PlusHighlight()
                        .padding(.trailing, 16)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .ignoresSafeArea(.container, edges: .bottom)
                        .transition(.opacity)
                }
                TipBubble(tip: tip) { accepted in
                    withAnimation(Motion.standard) { onTip(tip, accepted) }
                }
                .frame(maxWidth: tip == .voice ? 268 : .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: tip == .voice ? .bottomTrailing : .bottom)
                .ignoresSafeArea(.container, edges: .bottom)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(1)
            }

            if let toast {
                UndoToast(text: toast.text) {
                    toast.undo()
                    withAnimation(Motion.standard) { self.toast = nil }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 98)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(.container, edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    withAnimation(Motion.standard) { self.toast = nil }
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
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: habit)
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: snoozeHint)
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: tip)
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
        .confirmationDialog(
            Text(verbatim: postponing?.title ?? ""),
            isPresented: Binding(get: { postponing != nil }, set: { if !$0 { postponing = nil } }),
            titleVisibility: .visible,
            presenting: postponing
        ) { row in
            Button("In an hour") { onPostpone(row, .hour) }
            Button("Tomorrow morning") { onPostpone(row, .morning) }
            Button("Choose a time") { onPostpone(row, .custom) }
        }
    }

    private struct Toast: Identifiable {
        let id = UUID()
        let text: String
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
        // A dial is not mirrored in Arabic, and the drawn marks would not follow mirrored handles.
        .environment(\.layoutDirection, .leftToRight)
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
            toast = Toast(text: String(localized: "Moved to \(clockText(result.minutes))", bundle: .app, locale: .app), undo: undo)
        }
    }

    private func liftSummary(_ title: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: title)
                .font(.app(.golos, 17, weight: 600))
                .lineLimit(2)
            Text("move around the dial in 5-minute steps · let go to reschedule")
                .font(.app(.golos, 13))
                .foregroundStyle(Palette.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private func movingRow(_ row: HomeContent.Row, _ lift: DialLift) -> HomeContent.Row {
        let was = String(localized: "was \(clockText(lift.original))", bundle: .app, locale: .app)
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
                .lineLimit(2)
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

    private var scheduledButton: some View {
        Button(action: onScheduled) {
            HStack(spacing: 8) {
                Glyph(paths: Icons.list, size: 16, lineWidth: 2, color: Palette.text)
                Text("All scheduled")
                Text(verbatim: "\(scheduledCount)")
                    .font(.app(.jost, 16, weight: 500))
                    .foregroundStyle(Palette.accentText)
                Glyph(paths: Icons.chevron, size: 14, lineWidth: 2.2, color: Palette.secondary)
            }
        }
        .buttonStyle(RaisedChipStyle(radius: 20))
    }

    private enum Line: Identifiable {
        case reminder(HomeContent.Row)
        case event(HomeContent.Event)

        var id: String {
            switch self {
            case .reminder(let row): row.id
            case .event(let event): "event-\(event.id)"
            }
        }

        var date: Date {
            switch self {
            case .reminder(let row): row.occurrence
            case .event(let event): event.start
            }
        }
    }

    // Calendar events stand among the reminders by time, quieter and without a tick.
    private var lines: [Line] {
        (content.rows.map(Line.reminder) + content.events.map(Line.event)).sorted { $0.date < $1.date }
    }

    private func eventRow(_ event: HomeContent.Event) -> some View {
        HStack(spacing: 14) {
            Text(verbatim: event.time)
                .font(.app(.jost, 18, weight: 500))
                .monospacedDigit()
                .foregroundStyle(Palette.secondary)
                .timeColumn()
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: event.title)
                    .font(.app(.golos, 16))
                    .foregroundStyle(Palette.text.opacity(0.85))
                    .lineLimit(2)
                Text(verbatim: event.subtitle)
                    .font(.app(.golos, 12))
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if event.upcoming, !event.reminded {
                Button {
                    Feedback.play(.select)
                    onRemindEvent(event)
                } label: {
                    Text("Remind")
                }
                .buttonStyle(SmallButtonStyle(prominent: false, height: 32))
            }
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(lines) { line in
                switch line {
                case .event(let event):
                    eventRow(event)
                        .transition(.opacity)
                case .reminder(let row):
                    reminderLine(row)
                }
                if line.id != lines.last?.id {
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

    private func reminderLine(_ row: HomeContent.Row) -> some View {
        Group {
            let moving = lift.map { $0.holds(row) } ?? false
            AgendaRow(
                row: lift.map { moving ? movingRow(row, $0) : row } ?? row,
                onToggle: { onToggle(row) },
                onDelete: { remove(row.reminderID) },
                onPostpone: row.missed ? { postponing = row } : nil
            )
                .background {
                    if moving {
                        Palette.accent.opacity(0.09)
                            .padding(.horizontal, -16)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onOpen(row.reminderID) }
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var day: some View {
        VStack(spacing: 12) {
            if let alert {
                HomeNotice(alert: alert) { onAlert(alert) }
                    .transition(.opacity)
            }
            if content.rows.isEmpty && content.events.isEmpty {
                emptyDay
            } else {
                list
            }
            if !content.tiles.isEmpty, scheduledCount == 0 {
                tiles
            }
        }
    }

    private func remove(_ id: UUID) {
        guard let undo = onDelete(id) else { return }
        withAnimation(Motion.standard) {
            toast = Toast(text: String(localized: "Reminder deleted", bundle: .app, locale: .app), undo: undo)
        }
    }

    private var emptyDay: some View {
        VStack(spacing: 6) {
            if loadingAccount {
                ProgressView()
                    .padding(.bottom, 4)
                Text("Loading from your account…")
                    .font(.app(.golos, 16, weight: 600))
            } else {
                Text("Nothing for today")
                    .font(.app(.golos, 16, weight: 600))
                Text("Write below what and when to remind you")
                    .font(.app(.golos, 13))
                    .foregroundStyle(Palette.secondary)
            }
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
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .panel(radius: 18)
        .contentShape(Rectangle())
    }
}

#Preview {
    HomeScreen(content: SampleData.home)
}
