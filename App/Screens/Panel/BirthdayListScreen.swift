import RemaCore
import SwiftUI

enum BirthdayPatterns {
    // The title the import gave in each language, for birthdays added before they kept a name of their own.
    static let all: [String] = {
        let key = "Birthday of %@"
        var found = [key]
        for language in AppLanguage.allCases {
            guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"), let bundle = Bundle(path: path) else { continue }
            let pattern = bundle.localizedString(forKey: key, value: key, table: nil)
            if !found.contains(pattern) {
                found.append(pattern)
            }
        }
        return found
    }()
}

// The birthdays coming up and all of them, added from contacts or by hand.
struct BirthdayListScreen: View {
    let store: Store
    var now = Date()
    var calendar: Calendar = .current
    var locale: Locale = AppLanguage.current.locale
    let onOpen: (UUID) -> Void
    let onImport: () -> Void
    let onBack: () -> Void

    @State private var adding = false

    var body: some View {
        let entries = Birthdays.entries(store.reminders, today: LocalDate(now, in: calendar), patterns: BirthdayPatterns.all)
        let soon = entries.filter { $0.daysLeft <= Birthdays.soon }
        let all = entries.sorted { ($0.month, $0.day, $0.name) < ($1.month, $1.day, $1.name) }
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if entries.isEmpty {
                        VStack(spacing: 6) {
                            Text("No birthdays yet")
                                .font(.app(.golos, 16, weight: 600))
                            Text("Add one by hand with the plus or import them from contacts")
                                .font(.app(.golos, 13))
                                .foregroundStyle(Palette.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .padding(.horizontal, 16)
                        .panel()
                        .padding(.top, 14)
                    }
                    if !soon.isEmpty {
                        label(Text("Coming up"), accent: true, top: 14)
                        PanelList {
                            rows(soon)
                        }
                    }
                    if !all.isEmpty {
                        label(Text("All"), accent: false, top: soon.isEmpty ? 14 : 20)
                        PanelList {
                            rows(all)
                        }
                    }
                    PanelList {
                        NavigationRow(icon: Icons.people, iconColor: Palette.text, title: "Import from contacts", minHeight: 52, action: onImport) {
                            EmptyView()
                        }
                    }
                    .padding(.top, 14)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Palette.text)
        .pinnedHeader {
            ScreenHeader(title: "Birthdays", leading: .back, action: onBack) {
                RoundIconButton(icon: Icons.plus, label: "Add birthday") {
                    adding = true
                }
            }
        }
        .sheet(isPresented: $adding) {
            BirthdayAddSheet(store: store, now: now, calendar: calendar, locale: locale) {
                adding = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
            .presentationBackground(Palette.background)
        }
    }

    private func label(_ text: Text, accent: Bool, top: CGFloat) -> some View {
        text
            .font(.app(.golos, 12, weight: 600))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(accent ? Palette.accentText : Palette.secondary)
            .padding(.horizontal, 4)
            .padding(.top, top)
            .padding(.bottom, 8)
    }

    private func rows(_ entries: [BirthdayEntry]) -> some View {
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            Button {
                onOpen(entry.reminderID)
            } label: {
                HStack(spacing: 12) {
                    Avatar(name: entry.name, seed: entry.reminderID.uuidString)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: entry.name)
                            .font(.app(.golos, 16, weight: 500))
                            .lineLimit(1)
                        Text(verbatim: dateLine(entry))
                            .font(.app(.golos, 12))
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: left(entry))
                        .font(.app(.golos, 13))
                        .foregroundStyle(entry.daysLeft == 0 ? Palette.accentText : Palette.secondary)
                        .lineLimit(1)
                }
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            if index < entries.count - 1 {
                Hairline()
            }
        }
    }

    private func dateLine(_ entry: BirthdayEntry) -> String {
        let date = calendar.date(from: DateComponents(year: 2000, month: entry.month, day: entry.day, hour: 12)) ?? now
        let day = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.wide))
        guard let turning = entry.turning else { return day }
        return "\(day), \(String(localized: "turns \(turning)", bundle: .app, locale: .app))"
    }

    private func left(_ entry: BirthdayEntry) -> String {
        switch entry.daysLeft {
        case 0: String(localized: "today", bundle: .app, locale: .app)
        case 1: String(localized: "tomorrow", bundle: .app, locale: .app)
        case ...Birthdays.soon: String(localized: "in \(entry.daysLeft) days", bundle: .app, locale: .app)
        default: String(localized: "in \(max(1, Int((Double(entry.daysLeft) / 30.44).rounded()))) months", bundle: .app, locale: .app)
        }
    }
}

// A birthday by hand: whose, the date with the year if known, and how early to warn; it rings yearly at ten in the morning.
struct BirthdayAddSheet: View {
    let store: Store
    var now = Date()
    var calendar: Calendar = .current
    var locale: Locale = AppLanguage.current.locale
    let onClose: () -> Void

    enum Warning: Hashable {
        case none
        case day
        case threeDays
        case week

        var minutes: [Int] {
            switch self {
            case .none: []
            case .day: [1_440]
            case .threeDays: [4_320]
            case .week: [10_080]
            }
        }
    }

    @State private var name = ""
    @State private var day: Int
    @State private var month: Int
    @State private var year = 0
    @State private var warning = Warning.day
    @FocusState private var nameFocused: Bool

    init(store: Store, now: Date = Date(), calendar: Calendar = .current, locale: Locale = AppLanguage.current.locale, onClose: @escaping () -> Void) {
        self.store = store
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.onClose = onClose
        let today = LocalDate(now, in: calendar)
        _day = State(initialValue: today.day)
        _month = State(initialValue: today.month)
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var monthNames: [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        return formatter.monthSymbols ?? []
    }

    private var years: [Int] {
        let current = LocalDate(now, in: calendar).year
        return Array(stride(from: current, through: current - 110, by: -1))
    }

    private var next: LocalDate {
        Birthdays.coming(month: month, day: min(day, LocalDate.days(in: month, year: 2000)), from: LocalDate(now, in: calendar))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Birthday")
                    .font(.app(.jost, 26, weight: 500))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 22)
                Text("Add by hand")
                    .font(.app(.golos, 14))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 4)
                SectionLabel(text: "Full name")
                    .padding(.horizontal, 4)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                TextField(text: $name, prompt: Text("Name").foregroundColor(Palette.secondary)) {
                    Text("Full name")
                }
                .font(.app(.golos, 17))
                .tint(Palette.accent)
                .focused($nameFocused)
                .submitLabel(.done)
                .textContentType(.name)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .circular)
                        .fill(Palette.well)
                        .insetShadow(RoundedRectangle(cornerRadius: 16, style: .circular), Palette.wellShadow, blur: 3, y: 1)
                }
                .overlay(RoundedRectangle(cornerRadius: 16, style: .circular).strokeBorder(nameFocused ? Palette.accent : Palette.wellBorder, lineWidth: nameFocused ? 2 : 1))
                SectionLabel(text: "Date of birth")
                    .padding(.horizontal, 4)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                HStack(spacing: 0) {
                    Picker(selection: $day) {
                        ForEach(1...LocalDate.days(in: month, year: year == 0 ? 2000 : year), id: \.self) { value in
                            Text(verbatim: "\(value)").tag(value)
                        }
                    } label: {
                        Text("Day")
                    }
                    .frame(width: 64)
                    Picker(selection: $month) {
                        ForEach(Array(monthNames.enumerated()), id: \.offset) { index, value in
                            Text(verbatim: value).tag(index + 1)
                        }
                    } label: {
                        Text("Month")
                    }
                    .frame(maxWidth: .infinity)
                    Picker(selection: $year) {
                        Text(verbatim: "—").tag(0)
                        ForEach(years, id: \.self) { value in
                            Text(verbatim: "\(value)").tag(value)
                        }
                    } label: {
                        Text("Year")
                    }
                    .frame(width: 92)
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
                .clipped()
                .panel()
                .onChange(of: month) { _, _ in clampDay() }
                .onChange(of: year) { _, _ in clampDay() }
                Note("The year can be left out, then without the age")
                    .padding(.top, 8)
                SectionLabel(text: "Warn in advance")
                    .padding(.horizontal, 4)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                Segmented(options: [(Warning.none, "No"), (Warning.day, "A day before"), (Warning.threeDays, "3 days before"), (Warning.week, "A week before")], selection: $warning, fontSize: 13)
                Text(verbatim: summary)
                    .font(.app(.golos, 13))
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                Button("Add", action: add)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(trimmed.isEmpty)
                    .opacity(trimmed.isEmpty ? 0.5 : 1)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Palette.text)
    }

    private var summary: String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.wide)
        let date = calendar.date(from: DateComponents(year: next.year, month: next.month, day: next.day, hour: 12)) ?? now
        let birthday = date.formatted(style)
        guard let early = warning.minutes.first, let before = calendar.date(byAdding: .minute, value: -early, to: date) else {
            return String(localized: "I will remind on \(birthday) at 10:00", bundle: .app, locale: .app)
        }
        return String(localized: "I will remind on \(before.formatted(style)) and on \(birthday) at 10:00", bundle: .app, locale: .app)
    }

    private func clampDay() {
        day = min(day, LocalDate.days(in: month, year: year == 0 ? 2000 : year))
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        let reminder = Reminder(
            title: String(localized: "Birthday of \(trimmed)", bundle: .app, locale: .app),
            schedule: Schedule(start: next, time: LocalTime(hour: 10, minute: 0), rule: .yearly(month: month, day: day)),
            preAlerts: warning.minutes,
            createdAt: Date(),
            birthday: BirthdayNote(name: trimmed, year: year == 0 ? nil : year)
        )
        store.save(reminder)
        Feedback.play(.save)
        Notifier.shared.requestPermissionIfNeeded()
        onClose()
    }
}
