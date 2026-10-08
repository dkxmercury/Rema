import CoreSpotlight
import Foundation
import RemaCore
import UniformTypeIdentifiers

@MainActor
enum SpotlightIndex {
    static let domain = "uz.dkx.rema.reminders"
    private static var pending: Task<Void, Never>?

    static func scheduleUpdate() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await update()
        }
    }

    // With Face ID protection on, the titles stay out of the phone's search too.
    static func update() async {
        let index = CSSearchableIndex.default()
        try? await index.deleteSearchableItems(withDomainIdentifiers: [domain])
        guard !AppLock.shared.enabled else { return }
        let store = Store.shared
        let describer = Describer(locale: AppLanguage.current.locale)
        let now = Date()
        let items = store.activeReminders.map { reminder -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = reminder.title
            if let schedule = reminder.schedule, let next = Recurrence.next(schedule, after: now, limit: 1, calendar: .current).first {
                attributes.contentDescription = describer.dayAndTime(next, now: now)
            } else if !reminder.placeIDs.isEmpty {
                attributes.contentDescription = describer.placeText(reminder, places: store.places)
            }
            return CSSearchableItem(uniqueIdentifier: reminder.id.uuidString, domainIdentifier: domain, attributeSet: attributes)
        }
        guard !items.isEmpty else { return }
        try? await index.indexSearchableItems(items)
    }
}
