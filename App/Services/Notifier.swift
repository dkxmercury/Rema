import CoreLocation
import RemaCore
import UIKit
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    static let missedKey = "missedReminders"
    static let summaryKey = "dailySummary"

    @MainActor
    static var missedEnabled: Bool {
        Remote.shared.isOn(.missed) && (UserDefaults.standard.object(forKey: missedKey) as? Bool ?? true)
    }

    private var pending: Task<Void, Never>?
    @MainActor private var running: Task<Void, Never>?
    @MainActor private var again = false
    @MainActor private var background = UIBackgroundTaskIdentifier.invalid
    private var store: Store { Store.shared }

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(categories)
    }

    static func snoozeTitle(_ option: Int) -> String {
        switch option {
        case SnoozeOption.tomorrowMorning: return String(localized: "Tomorrow morning", bundle: .app, locale: .app)
        case SnoozeOption.thisEvening: return String(localized: "This evening", bundle: .app, locale: .app)
        case 5: return String(localized: "In 5 minutes", bundle: .app, locale: .app)
        case 10: return String(localized: "In 10 minutes", bundle: .app, locale: .app)
        case 15: return String(localized: "In 15 minutes", bundle: .app, locale: .app)
        case 30: return String(localized: "In 30 minutes", bundle: .app, locale: .app)
        case 120: return String(localized: "In 2 hours", bundle: .app, locale: .app)
        case 180: return String(localized: "In 3 hours", bundle: .app, locale: .app)
        default: return String(localized: "In an hour", bundle: .app, locale: .app)
        }
    }

    private static func snoozeIdentifier(_ option: Int) -> String {
        switch option {
        case SnoozeOption.tomorrowMorning: return "morning"
        case SnoozeOption.thisEvening: return "evening"
        default: return "snooze\(option)"
        }
    }

    private var categories: Set<UNNotificationCategory> {
        let done = UNNotificationAction(identifier: "done", title: String(localized: "Done", bundle: .app, locale: .app))
        let fifteenMinutes = UNNotificationAction(identifier: "snooze15", title: String(localized: "In 15 minutes", bundle: .app, locale: .app))
        let snoozes = (store.settings.snoozeOptions ?? SnoozeOption.standard).prefix(SnoozeOption.limit).map { option in
            UNNotificationAction(identifier: Self.snoozeIdentifier(option), title: Self.snoozeTitle(option))
        }
        let skip = UNNotificationAction(identifier: "skip", title: String(localized: "Skip today", bundle: .app, locale: .app))
        let call = UNNotificationAction(identifier: "call", title: String(localized: "Call", bundle: .app, locale: .app), options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "phone.fill"))
        let open = UNNotificationAction(identifier: "open", title: String(localized: "Open", bundle: .app, locale: .app), options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "safari"))
        return [
            UNNotificationCategory(identifier: "reminder", actions: [done] + snoozes, intentIdentifiers: []),
            UNNotificationCategory(identifier: "nag", actions: [done, fifteenMinutes, skip], intentIdentifiers: []),
            UNNotificationCategory(identifier: "place", actions: [done], intentIdentifiers: []),
            UNNotificationCategory(identifier: "reminder.call", actions: [call, done] + snoozes.prefix(2), intentIdentifiers: []),
            UNNotificationCategory(identifier: "reminder.open", actions: [open, done] + snoozes.prefix(2), intentIdentifiers: []),
            UNNotificationCategory(identifier: "nag.call", actions: [call, done, fifteenMinutes, skip], intentIdentifiers: []),
            UNNotificationCategory(identifier: "nag.open", actions: [open, done, fifteenMinutes, skip], intentIdentifiers: []),
            UNNotificationCategory(identifier: "place.call", actions: [call, done], intentIdentifiers: []),
            UNNotificationCategory(identifier: "place.open", actions: [open, done], intentIdentifiers: []),
        ]
    }

    // What was already shown stays in the shade after the account is gone unless it is taken down.
    func forgetDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.link.rawValue)

    static func contact(in text: String) -> (action: String, value: String)? {
        guard let detector else { return nil }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if match.resultType == .phoneNumber, let number = match.phoneNumber {
                let digits = number.filter { $0.isNumber || $0 == "+" }
                if digits.filter(\.isNumber).count >= 5 {
                    return ("call", digits)
                }
            } else if match.resultType == .link, let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                return ("open", url.absoluteString)
            }
        }
        return nil
    }

    // A person picked from the contacts wins over a number written in the title.
    private func addContact(of title: String, link: ContactLink? = nil, to content: UNMutableNotificationContent) {
        if let phone = link?.phone.filter({ $0.isNumber || $0 == "+" }), phone.filter(\.isNumber).count >= 5 {
            content.categoryIdentifier += ".call"
            content.userInfo["call"] = phone
            return
        }
        guard let contact = Self.contact(in: title) else { return }
        content.categoryIdentifier += ".\(contact.action)"
        content.userInfo[contact.action] = contact.value
    }

    func requestPermissionIfNeeded() {
        #if DEBUG
        // A system prompt over the filmed screen would spoil the recording.
        if DemoMode.isOn {
            return
        }
        #endif
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            await reschedule()
        }
    }

    func scheduleSoon() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await reschedule()
        }
    }

    // Rebuilds never overlap; a request that comes in during one runs right after it, and every caller waits for that.
    @MainActor
    func reschedule() async {
        pending?.cancel()
        if let running {
            again = true
            await running.value
            return
        }
        let task = Task { @MainActor in
            // Begun as the app leaves, a rebuild still has to finish instead of freezing halfway.
            holdBackground()
            repeat {
                again = false
                await rebuild()
            } while again
            running = nil
            releaseBackground()
        }
        running = task
        await task.value
    }

    @MainActor
    private func holdBackground() {
        guard background == .invalid else { return }
        background = UIApplication.shared.beginBackgroundTask(withName: "notifications") {
            MainActor.assumeIsolated { Notifier.shared.releaseBackground() }
        }
    }

    @MainActor
    private func releaseBackground() {
        guard background != .invalid else { return }
        UIApplication.shared.endBackgroundTask(background)
        background = .invalid
    }

    @MainActor
    private func rebuild() async {
        store.reloadIfChanged()
        let center = UNUserNotificationCenter.current()
        // Snooze buttons follow the settings, which another phone may have changed.
        center.setNotificationCategories(categories)
        let status = await center.notificationSettings().authorizationStatus
        NotificationAccess.shared.update(status)
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let now = Date()
        let followUp = Self.missedEnabled ? Int(Remote.shared.number(.missedFollowUp)) : nil
        let places = placeRequests()
        let summaries = summaryRequests(now: now)
        let weather = WeatherAdvisor.shared.notes(after: now)
        // Places and weather take their slots first; the planner picks what matters most for the rest.
        let plan = Scheduler.plan(reminders: store.reminders, settings: store.settings, now: now, calendar: .current, capacity: max(0, Scheduler.capacity - places.count - summaries.count - weather.count), followUp: followUp)
        var requests = places + summaries
        for note in weather {
            let content = UNMutableNotificationContent()
            content.title = note.title
            content.subtitle = WeatherAdvisor.mark
            content.body = note.body
            content.interruptionLevel = .passive
            content.threadIdentifier = "weather"
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: note.fireDate)
            requests.append(UNNotificationRequest(identifier: note.identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = body(for: item, now: now)
            content.sound = SoundPlayer.notificationSound(soundFor(item), settings: store.settings, sounds: store.sounds)
            content.categoryIdentifier = item.nag ? "nag" : "reminder"
            content.interruptionLevel = item.urgent ? .timeSensitive : .active
            content.threadIdentifier = item.reminderID.uuidString
            content.userInfo = ["reminder": item.reminderID.uuidString, "occurrence": item.occurrence.timeIntervalSince1970]
            // A number or a link in a friend's reminder is not a button to press; only one's own reminders get those.
            let owned = store.reminder(item.reminderID)
            if owned?.shared?.isMine != false {
                addContact(of: item.title, link: owned?.contact, to: content)
            }
            if item.kind == .missed {
                content.title = String(localized: "Not done: \(item.title)", bundle: .app, locale: .app)
                content.badge = NSNumber(value: max(1, Agenda.missed(item.fireDate, reminders: store.activeReminders, calendar: .current).count))
            }
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            requests.append(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        }
        // Only what is no longer wanted goes first and the rest lands over the old copies, so a rebuild cut short never leaves the phone silent.
        let wanted = Set(requests.map(\.identifier))
        let stale = await center.pendingNotificationRequests().map(\.identifier).filter { !wanted.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        for request in requests {
            try? await center.add(request)
        }
        let missed = Self.missedEnabled ? Agenda.missed(now, reminders: store.activeReminders, calendar: .current).count : 0
        try? await center.setBadgeCount(missed)
    }

    // In the morning the list of today, in the evening the list of tomorrow; a day with nothing gets no summary.
    @MainActor
    private func summaryRequests(now: Date) -> [UNNotificationRequest] {
        guard UserDefaults.standard.bool(forKey: Self.summaryKey) else { return [] }
        let calendar = Calendar.current
        let describer = Describer(locale: AppLanguage.current.locale)
        let start = calendar.startOfDay(for: now)
        var requests: [UNNotificationRequest] = []
        for offset in 0..<2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start), let next = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let morning = store.settings.morning
            let evening = store.settings.evening
            if let fire = calendar.date(bySettingHour: morning.hour, minute: morning.minute, second: 0, of: day), fire > now,
               let request = summary(of: day, today: true, at: fire, describer: describer, calendar: calendar) {
                requests.append(request)
            }
            if let fire = calendar.date(bySettingHour: evening.hour, minute: evening.minute, second: 0, of: day), fire > now,
               let request = summary(of: next, today: false, at: fire, describer: describer, calendar: calendar) {
                requests.append(request)
            }
        }
        return requests
    }

    @MainActor
    private func summary(of day: Date, today: Bool, at fire: Date, describer: Describer, calendar: Calendar) -> UNNotificationRequest? {
        let items = Agenda.day(day, reminders: store.activeReminders, calendar: calendar).filter { !$0.done }
        guard !items.isEmpty else { return nil }
        let lines = items.prefix(5).compactMap { item in
            store.reminder(item.reminderID).map { "\(describer.time(item.occurrence)) \($0.title)" }
        }
        let count = String(localized: "\(items.count) reminders", bundle: .app, locale: .app)
        let content = UNMutableNotificationContent()
        content.title = today ? String(localized: "Today, \(count)", bundle: .app, locale: .app) : String(localized: "Tomorrow, \(count)", bundle: .app, locale: .app)
        var body = lines.joined(separator: "\n")
        if items.count > lines.count {
            body += "\n" + String(localized: "\(items.count - lines.count) more", bundle: .app, locale: .app)
        }
        content.body = body
        content.interruptionLevel = .passive
        content.threadIdentifier = "summary"
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        return UNNotificationRequest(identifier: "summary.\(Int(fire.timeIntervalSince1970))", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    @MainActor
    private func placeRequests() -> [UNNotificationRequest] {
        guard LocationService.shared.allowed, Remote.shared.isOn(.places) else { return [] }
        var requests: [UNNotificationRequest] = []
        for reminder in store.activeReminders where !reminder.placeIDs.isEmpty {
            // A one-off reminder that is done stops watching its places too, a repeating one keeps them.
            if reminder.schedule?.rule == nil, reminder.completedThrough != nil { continue }
            for placeID in reminder.placeIDs {
                guard let place = store.livePlaces.first(where: { $0.id == placeID }) else { continue }
                let region = CLCircularRegion(center: place.coordinate, radius: max(place.radius, 100), identifier: "\(reminder.id.uuidString).\(place.id.uuidString)")
                region.notifyOnEntry = reminder.placeTrigger == .arrive
                region.notifyOnExit = reminder.placeTrigger == .leave
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                let arrival = reminder.placeTrigger == .leave ? String(localized: "Leaving: \(place.name)", bundle: .app, locale: .app) : String(localized: "Arrived: \(place.name)", bundle: .app, locale: .app)
                content.body = [arrival, listLine(reminder.id)].compactMap { $0 }.joined(separator: "\n")
                content.sound = SoundPlayer.notificationSound(reminder.sound, settings: store.settings, sounds: store.sounds)
                content.categoryIdentifier = "place"
                content.interruptionLevel = reminder.urgent ? .timeSensitive : .active
                content.threadIdentifier = reminder.id.uuidString
                content.userInfo = ["reminder": reminder.id.uuidString]
                if reminder.shared?.isMine != false {
                    addContact(of: reminder.title, link: reminder.contact, to: content)
                }
                let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
                requests.append(UNNotificationRequest(identifier: "place.\(region.identifier)", content: content, trigger: trigger))
                if requests.count >= Place.maximumCount {
                    return requests
                }
            }
        }
        return requests
    }

    private func soundFor(_ item: PlannedNotification) -> SoundChoice {
        store.reminder(item.reminderID)?.sound ?? item.sound
    }

    private func body(for item: PlannedNotification, now: Date) -> String {
        let describer = Describer(locale: AppLanguage.current.locale)
        let when = describer.dayAndTime(item.occurrence, now: item.fireDate).capitalizedFirst(.current)
        switch item.kind {
        case .main:
            return [when, listLine(item.reminderID)].compactMap { $0 }.joined(separator: "\n")
        case .early:
            return [String(localized: "\(when), reminding in advance", bundle: .app, locale: .app), listLine(item.reminderID)].compactMap { $0 }.joined(separator: "\n")
        case .snoozed:
            return String(localized: "Snoozed reminder", bundle: .app, locale: .app)
        case .missed:
            return String(localized: "It was at \(describer.time(item.occurrence)). Open to mark it or move it.", bundle: .app, locale: .app)
        case .nag(let index):
            let interval = store.reminder(item.reminderID)?.nagInterval ?? store.settings.nagInterval
            let next = index == Scheduler.nagRepeats ? String(localized: "This is the last reminder.", bundle: .app, locale: .app) : String(localized: "I'll repeat in \(interval) minutes until you tap Done.", bundle: .app, locale: .app)
            return "\(ordinal(index + 1)). \(next)"
        }
    }

    // What is still to tick, right in the notification, so the list is at hand in the shop.
    private func listLine(_ id: UUID) -> String? {
        let left = (store.reminder(id)?.items ?? []).filter { !$0.done }.map(\.text)
        guard !left.isEmpty else { return nil }
        let shown = left.prefix(8).joined(separator: ", ")
        return left.count > 8 ? "\(shown)…" : shown
    }

    private func ordinal(_ number: Int) -> String {
        switch number {
        case 2: return String(localized: "Reminding for the 2nd time", bundle: .app, locale: .app)
        case 3: return String(localized: "Reminding for the 3rd time", bundle: .app, locale: .app)
        case 4: return String(localized: "Reminding for the 4th time", bundle: .app, locale: .app)
        case 5: return String(localized: "Reminding for the 5th time", bundle: .app, locale: .app)
        case 6: return String(localized: "Reminding for the 6th time", bundle: .app, locale: .app)
        case 7: return String(localized: "Reminding for the 7th time", bundle: .app, locale: .app)
        case 8: return String(localized: "Reminding for the 8th time", bundle: .app, locale: .app)
        case 9: return String(localized: "Reminding for the 9th time", bundle: .app, locale: .app)
        case 10: return String(localized: "Reminding for the 10th time", bundle: .app, locale: .app)
        case 11: return String(localized: "Reminding for the 11th time", bundle: .app, locale: .app)
        case 12: return String(localized: "Reminding for the 12th time", bundle: .app, locale: .app)
        default: return String(localized: "Reminding for the 13th time", bundle: .app, locale: .app)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // The extension has left the friend's change in the inbox; the open app takes it in and asks for the rest.
        if notification.request.content.userInfo["rema"] != nil {
            Task { @MainActor in
                store.reloadIfChanged()
                SharedService.shared.kick()
            }
        }
        if notification.request.content.userInfo["remaNews"] != nil {
            Task { @MainActor in await NewsService.shared.refresh(force: true) }
        }
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        Task { @MainActor in
            if action == "call" || action == "open" {
                if let value = info[action] as? String, let url = URL(string: action == "call" ? "tel:\(value)" : value) {
                    await UIApplication.shared.open(url)
                }
                completionHandler()
                return
            }
            // A news push opens that news, or the list when it came without one.
            if let news = info["remaNews"] as? String {
                if action == UNNotificationDefaultActionIdentifier {
                    NewsService.shared.openRequest = news
                }
                completionHandler()
                return
            }
            if info["rema"] != nil {
                store.reloadIfChanged()
                SharedService.shared.kick()
                if action == UNNotificationDefaultActionIdentifier, let raw = info["reminder"] as? String, let id = UUID(uuidString: raw) {
                    RootNavigation.shared.openRequest = id
                }
                completionHandler()
                return
            }
            if let raw = info["reminder"] as? String, let id = UUID(uuidString: raw) {
                let occurrence = Date(timeIntervalSince1970: info["occurrence"] as? Double ?? Date().timeIntervalSince1970)
                store.reloadIfChanged()
                apply(action, to: id, occurrence: occurrence)
            }
            await reschedule()
            completionHandler()
        }
    }

    // A snooze is personal: for a shared reminder the tick covers the time that was put off, not the time it was put off to,
    // which may already be the next one for everybody.
    @MainActor
    private func doneThrough(_ id: UUID, occurrence: Date, now: Date) -> Date {
        guard let reminder = store.reminder(id), let snoozed = reminder.snoozedUntil else { return occurrence }
        guard reminder.shared != nil, let schedule = reminder.schedule else { return max(occurrence, snoozed) }
        let from = max(reminder.completedThrough ?? .distantPast, now.addingTimeInterval(-2 * 86_400))
        return Recurrence.next(schedule, after: from, limit: 200, calendar: .current).last { $0 <= now } ?? occurrence
    }

    @MainActor
    private func apply(_ action: String, to id: UUID, occurrence: Date) {
        let now = Date()
        switch action {
        case "done":
            store.complete(id, through: doneThrough(id, occurrence: occurrence, now: now))
        case "skip":
            store.skip(id, through: max(occurrence, store.reminder(id)?.snoozedUntil ?? occurrence))
        case "evening":
            let calendar = Calendar.current
            let evening = store.settings.evening
            var date = calendar.date(bySettingHour: evening.hour, minute: evening.minute, second: 0, of: now) ?? now
            if date <= now {
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            }
            store.snooze(id, until: date)
        case let snooze where snooze.hasPrefix("snooze"):
            if let minutes = Int(snooze.dropFirst(6)), minutes > 0 {
                store.snooze(id, until: now.addingTimeInterval(Double(minutes) * 60))
            }
        case "morning":
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            let morning = store.settings.morning
            let date = calendar.date(bySettingHour: morning.hour, minute: morning.minute, second: 0, of: tomorrow) ?? tomorrow
            store.snooze(id, until: date)
        default:
            break
        }
    }
}
