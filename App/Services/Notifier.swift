import CoreLocation
import RemaCore
import UIKit
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    static let missedKey = "missedReminders"

    @MainActor
    static var missedEnabled: Bool {
        Remote.shared.isOn(.missed) && (UserDefaults.standard.object(forKey: missedKey) as? Bool ?? true)
    }

    private var pending: Task<Void, Never>?
    private var store: Store { Store.shared }

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(categories)
    }

    private var categories: Set<UNNotificationCategory> {
        let done = UNNotificationAction(identifier: "done", title: String(localized: "Done"))
        let tenMinutes = UNNotificationAction(identifier: "snooze10", title: String(localized: "In 10 minutes"))
        let fifteenMinutes = UNNotificationAction(identifier: "snooze15", title: String(localized: "In 15 minutes"))
        let hour = UNNotificationAction(identifier: "snooze60", title: String(localized: "In an hour"))
        let morning = UNNotificationAction(identifier: "morning", title: String(localized: "Tomorrow morning"))
        let skip = UNNotificationAction(identifier: "skip", title: String(localized: "Skip today"))
        let call = UNNotificationAction(identifier: "call", title: String(localized: "Call"), options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "phone.fill"))
        let open = UNNotificationAction(identifier: "open", title: String(localized: "Open"), options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "safari"))
        return [
            UNNotificationCategory(identifier: "reminder", actions: [done, tenMinutes, hour, morning], intentIdentifiers: []),
            UNNotificationCategory(identifier: "nag", actions: [done, fifteenMinutes, skip], intentIdentifiers: []),
            UNNotificationCategory(identifier: "place", actions: [done], intentIdentifiers: []),
            UNNotificationCategory(identifier: "reminder.call", actions: [call, done, tenMinutes, hour], intentIdentifiers: []),
            UNNotificationCategory(identifier: "reminder.open", actions: [open, done, tenMinutes, hour], intentIdentifiers: []),
            UNNotificationCategory(identifier: "nag.call", actions: [call, done, fifteenMinutes, skip], intentIdentifiers: []),
            UNNotificationCategory(identifier: "nag.open", actions: [open, done, fifteenMinutes, skip], intentIdentifiers: []),
            UNNotificationCategory(identifier: "place.call", actions: [call, done], intentIdentifiers: []),
            UNNotificationCategory(identifier: "place.open", actions: [open, done], intentIdentifiers: []),
        ]
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

    private func addContact(of title: String, to content: UNMutableNotificationContent) {
        guard let contact = Self.contact(in: title) else { return }
        content.categoryIdentifier += ".\(contact.action)"
        content.userInfo[contact.action] = contact.value
    }

    func requestPermissionIfNeeded() {
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

    @MainActor
    func reschedule() async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let now = Date()
        let followUp = Self.missedEnabled ? Int(Remote.shared.number(.missedFollowUp)) : nil
        let plan = Scheduler.plan(reminders: store.reminders, settings: store.settings, now: now, calendar: .current, followUp: followUp)
        let places = placeRequests()
        let weather = WeatherAdvisor.shared.notes(after: now)
        center.removeAllPendingNotificationRequests()
        for request in places {
            try? await center.add(request)
        }
        for note in weather {
            let content = UNMutableNotificationContent()
            content.title = note.title
            content.body = note.body
            content.interruptionLevel = .passive
            content.threadIdentifier = "weather"
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: note.fireDate)
            try? await center.add(UNNotificationRequest(identifier: note.identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
        for item in plan.prefix(max(0, 60 - places.count - weather.count)) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = body(for: item, now: now)
            content.sound = SoundPlayer.notificationSound(soundFor(item), settings: store.settings, sounds: store.sounds)
            content.categoryIdentifier = item.nag ? "nag" : "reminder"
            content.interruptionLevel = item.urgent ? .timeSensitive : .active
            content.threadIdentifier = item.reminderID.uuidString
            content.userInfo = ["reminder": item.reminderID.uuidString, "occurrence": item.occurrence.timeIntervalSince1970]
            addContact(of: item.title, to: content)
            if item.kind == .missed {
                content.title = String(localized: "Not done: \(item.title)")
                content.badge = NSNumber(value: Agenda.missed(item.fireDate, reminders: store.activeReminders, calendar: .current).count)
            }
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        }
        let missed = Self.missedEnabled ? Agenda.missed(now, reminders: store.activeReminders, calendar: .current).count : 0
        try? await center.setBadgeCount(missed)
    }

    @MainActor
    private func placeRequests() -> [UNNotificationRequest] {
        guard LocationService.shared.allowed, Remote.shared.isOn(.places) else { return [] }
        var requests: [UNNotificationRequest] = []
        for reminder in store.activeReminders where !reminder.placeIDs.isEmpty {
            if reminder.isPlaceOnly, reminder.completedThrough != nil { continue }
            for placeID in reminder.placeIDs {
                guard let place = store.livePlaces.first(where: { $0.id == placeID }) else { continue }
                let region = CLCircularRegion(center: place.coordinate, radius: max(place.radius, 100), identifier: "\(reminder.id.uuidString).\(place.id.uuidString)")
                region.notifyOnEntry = reminder.placeTrigger == .arrive
                region.notifyOnExit = reminder.placeTrigger == .leave
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.placeTrigger == .leave ? String(localized: "Leaving: \(place.name)") : String(localized: "Arrived: \(place.name)")
                content.sound = SoundPlayer.notificationSound(reminder.sound, settings: store.settings, sounds: store.sounds)
                content.categoryIdentifier = "place"
                content.interruptionLevel = reminder.urgent ? .timeSensitive : .active
                content.threadIdentifier = reminder.id.uuidString
                content.userInfo = ["reminder": reminder.id.uuidString]
                addContact(of: reminder.title, to: content)
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
            return when
        case .early:
            return String(localized: "\(when), reminding in advance")
        case .snoozed:
            return String(localized: "Snoozed reminder")
        case .missed:
            return String(localized: "It was at \(describer.time(item.occurrence)). Open to mark it or move it.")
        case .nag(let index):
            let interval = store.reminder(item.reminderID)?.nagInterval ?? store.settings.nagInterval
            return "\(ordinal(index + 1)). \(String(localized: "I'll repeat in \(interval) minutes until you tap Done."))"
        }
    }

    private func ordinal(_ number: Int) -> String {
        switch number {
        case 2: return String(localized: "Reminding for the 2nd time")
        case 3: return String(localized: "Reminding for the 3rd time")
        case 4: return String(localized: "Reminding for the 4th time")
        case 5: return String(localized: "Reminding for the 5th time")
        case 6: return String(localized: "Reminding for the 6th time")
        case 7: return String(localized: "Reminding for the 7th time")
        case 8: return String(localized: "Reminding for the 8th time")
        case 9: return String(localized: "Reminding for the 9th time")
        case 10: return String(localized: "Reminding for the 10th time")
        case 11: return String(localized: "Reminding for the 11th time")
        case 12: return String(localized: "Reminding for the 12th time")
        default: return String(localized: "Reminding for the 13th time")
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
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
            if let raw = info["reminder"] as? String, let id = UUID(uuidString: raw) {
                let occurrence = Date(timeIntervalSince1970: info["occurrence"] as? Double ?? Date().timeIntervalSince1970)
                apply(action, to: id, occurrence: occurrence)
            }
            await reschedule()
            completionHandler()
        }
    }

    @MainActor
    private func apply(_ action: String, to id: UUID, occurrence: Date) {
        let now = Date()
        switch action {
        case "done", "skip":
            store.complete(id, through: max(occurrence, store.reminder(id)?.snoozedUntil ?? occurrence))
        case "snooze10":
            store.snooze(id, until: now.addingTimeInterval(600))
        case "snooze15":
            store.snooze(id, until: now.addingTimeInterval(900))
        case "snooze60":
            store.snooze(id, until: now.addingTimeInterval(3600))
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
