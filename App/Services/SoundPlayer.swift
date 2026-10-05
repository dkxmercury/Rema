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
            guard let sound = sounds.first(where: { $0.id == id }) else { return nil }
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
            guard let sound = sounds.first(where: { $0.id == id }) else { return .default }
            return UNNotificationSound(named: UNNotificationSoundName(sound.fileName))
        }
    }
}
