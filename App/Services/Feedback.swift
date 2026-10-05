import AudioToolbox
import UIKit

enum Feedback {
    enum Event: String, CaseIterable {
        case check
        case uncheck
        case toggle
        case select
        case delete
        case save
        case error
    }

    static let hapticsKey = "feedback.haptics"
    static let soundsKey = "feedback.sounds"

    static var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: hapticsKey) as? Bool ?? true
    }

    static var soundsEnabled: Bool {
        UserDefaults.standard.object(forKey: soundsKey) as? Bool ?? true
    }

    private static var sounds: [Event: SystemSoundID] = [:]

    static func play(_ event: Event) {
        if hapticsEnabled {
            haptic(event)
        }
        if soundsEnabled {
            sound(event)
        }
    }

    private static func haptic(_ event: Event) {
        switch event {
        case .check:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .uncheck, .toggle, .select:
            UISelectionFeedbackGenerator().selectionChanged()
        case .delete:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .save:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private static func sound(_ event: Event) {
        if let id = sounds[event] {
            AudioServicesPlaySystemSound(id)
            return
        }
        let url = SoundLibrary.url(event)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr else { return }
        sounds[event] = id
        AudioServicesPlaySystemSound(id)
    }
}
