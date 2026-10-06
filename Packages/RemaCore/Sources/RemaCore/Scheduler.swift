import Foundation

public struct PlannedNotification: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case main
        case early(minutes: Int)
        case nag(index: Int)
        case snoozed
        case missed
    }

    public let reminderID: UUID
    public let identifier: String
    public let fireDate: Date
    public let occurrence: Date
    public let kind: Kind
    public let title: String
    public let urgent: Bool
    public let nag: Bool
    public let sound: SoundChoice
}

public enum Scheduler {
    public static let capacity = 60
    public static let nagRepeats = 12
    static let occurrencesPerReminder = 8

    public static func plan(
        reminders: [Reminder],
        settings: Settings,
        now: Date,
        calendar: Calendar,
        capacity: Int = Scheduler.capacity,
        followUp: Int? = nil
    ) -> [PlannedNotification] {
        var planned: [PlannedNotification] = []
        for reminder in reminders where reminder.deletedAt == nil {
            planned.append(contentsOf: plan(reminder, settings: settings, now: now, calendar: calendar, followUp: followUp))
        }
        return Array(planned.sorted { lhs, rhs in
            lhs.fireDate == rhs.fireDate ? lhs.identifier < rhs.identifier : lhs.fireDate < rhs.fireDate
        }.prefix(capacity))
    }

    static func plan(_ reminder: Reminder, settings: Settings, now: Date, calendar: Calendar, followUp: Int? = nil) -> [PlannedNotification] {
        var result: [PlannedNotification] = []
        let interval = max(1, reminder.nagInterval ?? settings.nagInterval)

        func add(_ kind: PlannedNotification.Kind, at date: Date, occurrence: Date) {
            guard date > now else { return }
            result.append(PlannedNotification(
                reminderID: reminder.id,
                identifier: identifier(reminder.id, occurrence: occurrence, kind: kind),
                fireDate: date,
                occurrence: occurrence,
                kind: kind,
                title: reminder.title,
                urgent: reminder.urgent,
                nag: reminder.nag,
                sound: reminder.sound
            ))
        }

        if let snoozed = reminder.snoozedUntil, snoozed > now {
            add(.snoozed, at: snoozed, occurrence: snoozed)
            if reminder.nag {
                for index in 1...nagRepeats {
                    add(.nag(index: index), at: snoozed.addingTimeInterval(Double(index * interval) * 60), occurrence: snoozed)
                }
            }
        }

        guard let schedule = reminder.schedule else { return result }
        // A follow-up belongs to an occurrence that may already be past, so the search starts that much earlier.
        let missedTail = reminder.nag ? 0 : Double(followUp ?? 0) * 60
        let tail = reminder.nag ? Double(nagRepeats * interval) * 60 : missedTail
        var from = now.addingTimeInterval(-tail)
        if let done = reminder.completedThrough, done > from {
            from = done
        }
        let occurrences = Recurrence.next(schedule, after: from, limit: occurrencesPerReminder, calendar: calendar)
        for occurrence in occurrences {
            if let snoozed = reminder.snoozedUntil, snoozed > now, occurrence <= now {
                continue
            }
            add(.main, at: occurrence, occurrence: occurrence)
            for minutes in Set(reminder.preAlerts) where minutes > 0 {
                add(.early(minutes: minutes), at: occurrence.addingTimeInterval(-Double(minutes) * 60), occurrence: occurrence)
            }
            if reminder.nag {
                for index in 1...nagRepeats {
                    add(.nag(index: index), at: occurrence.addingTimeInterval(Double(index * interval) * 60), occurrence: occurrence)
                }
            } else if let followUp, followUp > 0 {
                add(.missed, at: occurrence.addingTimeInterval(Double(followUp) * 60), occurrence: occurrence)
            }
        }
        return result
    }

    public static func identifier(_ id: UUID, occurrence: Date, kind: PlannedNotification.Kind) -> String {
        let tag: String
        switch kind {
        case .main: tag = "main"
        case .early(let minutes): tag = "early\(minutes)"
        case .nag(let index): tag = "nag\(index)"
        case .snoozed: tag = "snoozed"
        case .missed: tag = "missed"
        }
        return "\(id.uuidString).\(Int(occurrence.timeIntervalSince1970)).\(tag)"
    }

    public static func reminderID(fromIdentifier identifier: String) -> UUID? {
        guard let head = identifier.split(separator: ".").first else { return nil }
        return UUID(uuidString: String(head))
    }
}
