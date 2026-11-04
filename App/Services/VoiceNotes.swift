import AVFoundation
import RemaCore

@MainActor
@Observable
final class VoiceRecorder {
    enum Phase {
        case starting
        case recording
        case finished
        case denied
        case failed
    }

    static let bars = 30

    private(set) var phase: Phase = .starting
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels: [Float] = []
    let file: URL
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?

    init(file: URL) {
        self.file = file
    }

    // A recording frozen in the middle, for the screenshots where there is no microphone.
    init(file: URL, elapsed: TimeInterval, levels: [Float]) {
        self.file = file
        self.elapsed = elapsed
        self.levels = levels
        phase = .recording
    }

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            phase = .denied
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            // IMA4 mono is what a notification can play and what the account keeps, so the file needs no second pass.
            let recorder = try AVAudioRecorder(url: file, settings: [
                AVFormatIDKey: kAudioFormatAppleIMA4,
                AVSampleRateKey: 22_050,
                AVNumberOfChannelsKey: 1,
            ])
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: CustomSound.maximumSeconds) else {
                phase = .failed
                return
            }
            self.recorder = recorder
            phase = .recording
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } catch {
            phase = .failed
        }
    }

    private func tick() {
        guard let recorder else { return }
        guard recorder.isRecording else {
            phase = .finished
            return
        }
        recorder.updateMeters()
        let level = max(0, min(1, (recorder.averagePower(forChannel: 0) + 50) / 50))
        levels.append(level)
        if levels.count > Self.bars {
            levels.removeFirst(levels.count - Self.bars)
        }
        elapsed = recorder.currentTime
    }

    // How long the note is, read back from the file; nil when nothing worth keeping was said.
    func stop() -> TimeInterval? {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let audio = try? AVAudioFile(forReading: file), audio.fileFormat.sampleRate > 0 else { return nil }
        let seconds = Double(audio.length) / audio.fileFormat.sampleRate
        return seconds >= 0.5 ? min(seconds, CustomSound.maximumSeconds) : nil
    }

    func discard() {
        _ = stop()
        try? FileManager.default.removeItem(at: file)
    }
}

@MainActor
@Observable
final class VoicePlayer {
    static let shared = VoicePlayer()

    private(set) var playing: UUID?
    private(set) var paused = false
    private(set) var current: TimeInterval = 0
    private(set) var progress: Double = 0
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?

    func toggle(_ sound: CustomSound) {
        if playing == sound.id, let player {
            if player.isPlaying {
                player.pause()
                paused = true
            } else {
                player.play()
                paused = false
            }
            return
        }
        play(sound)
    }

    // Played over the silent switch on purpose: the person asked to hear it.
    func play(_ sound: CustomSound) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback)
        try? session.setActive(true)
        guard let player = try? AVAudioPlayer(contentsOf: SoundLibrary.folder.appendingPathComponent(sound.fileName)) else { return }
        player.play()
        self.player = player
        playing = sound.id
        paused = false
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        playing = nil
        paused = false
        current = 0
        progress = 0
    }

    private func tick() {
        guard let player else { return }
        if !player.isPlaying, !paused {
            stop()
            return
        }
        current = player.currentTime
        progress = player.duration > 0 ? player.currentTime / player.duration : 0
    }
}

enum VoiceNotes {
    // The note a reminder plays: its own, or the one a friend recorded in a shared reminder once its file is here.
    static func note(of reminder: Reminder, sounds: [CustomSound]) -> CustomSound? {
        if let own = reminder.voiceNote(in: sounds) {
            return own
        }
        guard let shared = reminder.shared, !shared.isMine, let voice = shared.voice else { return nil }
        let note = CustomSound(id: voice.id, name: reminder.title, duration: voice.duration, createdAt: reminder.createdAt, reminderID: reminder.id)
        return FileManager.default.fileExists(atPath: SoundLibrary.folder.appendingPathComponent(note.fileName).path) ? note : nil
    }

    // A friend's note comes down once, through the shared reminder it is in; the name of the file is only its id.
    @MainActor
    static func fetchShared(token: String) async {
        var fetched = false
        for reminder in Store.shared.activeReminders {
            guard let shared = reminder.shared, !shared.isMine, let voice = shared.voice else { continue }
            let file = SoundLibrary.folder.appendingPathComponent(CustomSound(id: voice.id, name: "", duration: 0, createdAt: Date()).fileName)
            guard !FileManager.default.fileExists(atPath: file.path),
                  let data = try? await Backend.raw("GET", "/api/rema/shared/\(reminder.id.uuidString)/voice", token: token),
                  data.count <= 1_100_000, data.prefix(4) == Data("caff".utf8)
            else { continue }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? data.write(to: file, options: .atomic)) != nil {
                fetched = true
            }
        }
        if fetched {
            Notifier.shared.scheduleSoon()
        }
    }
}

enum VoiceShape {
    // Loudness of the note in equal slices, for the bars of the player.
    static func levels(of sound: CustomSound, bars: Int = VoiceRecorder.bars) -> [Float] {
        let url = SoundLibrary.folder.appendingPathComponent(sound.fileName)
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let samples = buffer.floatChannelData?[0]
        else { return Array(repeating: 0.3, count: bars) }
        let count = Int(buffer.frameLength)
        let size = max(1, count / bars)
        var levels: [Float] = []
        for bar in 0..<bars {
            let start = bar * size
            let end = min(count, start + size)
            guard start < end else {
                levels.append(0)
                continue
            }
            var sum: Float = 0
            for index in start..<end {
                sum += samples[index] * samples[index]
            }
            levels.append((sum / Float(end - start)).squareRoot())
        }
        let peak = levels.max() ?? 0
        return levels.map { peak > 0 ? max(0.12, $0 / peak) : 0.12 }
    }
}

extension TimeInterval {
    var clock: String {
        let seconds = Int(self.rounded(.down))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
