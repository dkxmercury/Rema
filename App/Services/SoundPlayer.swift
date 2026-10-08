import AVFoundation
import RemaCore
import UserNotifications

enum SoundPlayer {
    private static var player: AVAudioPlayer?

    static var librarySounds: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Sounds", isDirectory: true)
    }

    static func resolve(_ choice: SoundChoice, settings: Settings) -> SoundChoice {
        if case .standard = choice {
            if case .standard = settings.defaultSound {
                return .builtIn(BuiltInSound.mechanika.rawValue)
            }
            return settings.defaultSound
        }
        return choice
    }

    static func url(for choice: SoundChoice, settings: Settings, sounds: [CustomSound]) -> URL? {
        switch resolve(choice, settings: settings) {
        case .standard:
            return nil
        case .builtIn(let id):
            guard let file = BuiltInSound(rawValue: id)?.fileName else { return nil }
            return librarySounds.appendingPathComponent(file)
        case .custom(let id):
            // A deleted sound falls back to Mechanika, the same name the screens show for it.
            guard let sound = sounds.first(where: { $0.id == id && $0.deletedAt == nil }) else {
                return url(for: .builtIn(BuiltInSound.mechanika.rawValue), settings: settings, sounds: sounds)
            }
            return librarySounds.appendingPathComponent(sound.fileName)
        }
    }

    static func preview(_ choice: SoundChoice, settings: Settings, sounds: [CustomSound]) {
        guard let url = url(for: choice, settings: settings, sounds: sounds) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    static func notificationSound(_ choice: SoundChoice, settings: Settings, sounds: [CustomSound]) -> UNNotificationSound? {
        switch resolve(choice, settings: settings) {
        case .standard:
            return .default
        case .builtIn(let id):
            guard let file = BuiltInSound(rawValue: id)?.fileName else { return nil }
            return UNNotificationSound(named: UNNotificationSoundName(file))
        case .custom(let id):
            guard let sound = sounds.first(where: { $0.id == id && $0.deletedAt == nil }) else { return notificationSound(.builtIn(BuiltInSound.mechanika.rawValue), settings: settings, sounds: sounds) }
            return UNNotificationSound(named: UNNotificationSoundName(sound.fileName))
        }
    }
}
