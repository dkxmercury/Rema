import ActivityKit
import Foundation

struct ReminderActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var due: Date
        var start: Date
        var urgent: Bool
    }

    var reminderID: String
}
