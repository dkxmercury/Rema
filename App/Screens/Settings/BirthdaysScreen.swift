import RemaCore
import SwiftUI

struct BirthdaysScreen: View {
    let store: Store
    var now: Date = Date()
    var calendar: Calendar = .current
    var locale: Locale = AppLanguage.current.locale
    let onBack: () -> Void

    @State private var contacts: [BirthdayContact] = []
    @State private var chosen: Set<String> = []
    @State private var loading = true
    @State private var denied = false

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(denied ? LocalizedStringKey("Allow access to contacts in Settings to find birthdays.") : LocalizedStringKey("Rema found birthdays in your contacts. Tick the ones to be reminded of every year."))
                        .font(.app(.golos, 15))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.top, 14)
                    if loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    } else if !denied && contacts.isEmpty {
                        Text("No birthdays in your contacts")
                            .font(.app(.golos, 16, weight: 600))
                            .foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .panel()
                            .padding(.top, 14)
                    } else if !contacts.isEmpty {
                        SectionLabel(text: "In Contacts")
                            .padding(.horizontal, 4)
                            .padding(.top, 20)
                            .padding(.bottom, 8)
                        PanelList {
                            ForEach(Array(contacts.enumerated()), id: \.element.id) { index, contact in
                                row(contact)
                                if index < contacts.count - 1 {
                                    Hairline()
                                }
                            }
                        }
                        PanelList {
                            HStack(spacing: 12) {
                                Glyph(paths: Icons.clock, size: 20, lineWidth: 2, color: Palette.text)
                                Text("When")
                                    .font(.app(.golos, 16, weight: 500))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("at 10:00 and a day before")
                                    .font(.app(.golos, 14))
                                    .foregroundStyle(Palette.secondary)
                            }
                            .frame(minHeight: 52)
                        }
                        .padding(.top, 12)
                    }
                    if denied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Settings")
                        }
                        .buttonStyle(SmallButtonStyle(prominent: false))
                        .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "Birthdays", leading: .back, action: onBack)
            }
            if !chosen.isEmpty {
                PrimaryBar(action: add) {
                    Text(verbatim: String(localized: "Add \(chosen.count)", bundle: .app, locale: .app))
                        .contentTransition(.numericText())
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: chosen)
        .task {
            if !ContactsFeed.authorized {
                denied = !(await ContactsFeed.requestAccess())
            }
            let found = await Task.detached { ContactsFeed.birthdays() }.value
            contacts = found.sorted { next($0) < next($1) }
            loading = false
        }
    }

    private func next(_ contact: BirthdayContact) -> LocalDate {
        let today = LocalDate(now, in: calendar)
        let day = { (year: Int) in LocalDate(year: year, month: contact.month, day: min(contact.day, LocalDate.days(in: contact.month, year: year))) }
        let thisYear = day(today.year)
        return thisYear >= today ? thisYear : day(today.year + 1)
    }

    private func title(_ contact: BirthdayContact) -> String {
        String(localized: "Birthday of \(contact.name)", bundle: .app, locale: .app)
    }

    private func added(_ contact: BirthdayContact) -> Bool {
        store.activeReminders.contains { reminder in
            guard reminder.title == title(contact), case .yearly(let month, let day) = reminder.schedule?.rule else { return false }
            return month == contact.month && day == contact.day
        }
    }

    private func row(_ contact: BirthdayContact) -> some View {
        let done = added(contact)
        let on = done || chosen.contains(contact.id)
        let reference = calendar.date(from: DateComponents(year: 2000, month: contact.month, day: contact.day, hour: 12)) ?? now
        return Button {
            guard !done else { return }
            Feedback.play(on ? .uncheck : .check)
            if on {
                chosen.remove(contact.id)
            } else {
                chosen.insert(contact.id)
            }
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: String(contact.name.prefix(1)).uppercased())
                    .font(.app(.golos, 17, weight: 600))
                    .foregroundStyle(Palette.accentText)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Palette.accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: contact.name)
                        .font(.app(.golos, 16, weight: 500))
                        .lineLimit(1)
                    Text(verbatim: done ? String(localized: "already in Rema", bundle: .app, locale: .app) : reference.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.wide)))
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CheckBox(isOn: on)
                    .opacity(done ? 0.5 : 1)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(done)
    }

    // Every birthday rings yearly at ten in the morning and once the day before.
    private func add() {
        for contact in contacts where chosen.contains(contact.id) && !added(contact) {
            let reminder = Reminder(
                title: title(contact),
                schedule: Schedule(start: next(contact), time: LocalTime(hour: 10, minute: 0), rule: .yearly(month: contact.month, day: contact.day)),
                preAlerts: [1_440],
                createdAt: Date()
            )
            store.save(reminder)
        }
        Feedback.play(.save)
        Notifier.shared.requestPermissionIfNeeded()
        chosen = []
        onBack()
    }
}
