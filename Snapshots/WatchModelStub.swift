import Observation
import RemaCore

@Observable
final class WatchModel {
    var payload: WatchPayload?

    init(payload: WatchPayload?) {
        self.payload = payload
    }

    func toggle(_ item: WatchItem) {}
}
