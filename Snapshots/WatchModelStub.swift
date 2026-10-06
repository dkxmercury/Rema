import Foundation
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

// The watch screen is compiled into this bundle with its own copy of the language settings.
enum WatchLanguage {
    static func use(_ code: String?) {
        AppFonts.languageCode = code ?? Bundle.main.preferredLocalizations.first ?? "en"
        Bundle.app = code.flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }.flatMap(Bundle.init(path:)) ?? .main
    }
}
