import AVFoundation
import Observation
import Speech

@Observable
final class VoiceRecognizer {
    var transcript = ""
    var listening = false
    var level: Double = 0
    var failure: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    func start(locale: Locale, hints: [String] = []) {
        failure = nil
        transcript = ""
        Task { @MainActor in
            let speech = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard speech == .authorized else {
                failure = String(localized: "Allow speech recognition in Settings to dictate reminders.", bundle: .app, locale: .app)
                return
            }
            guard await AVAudioApplication.requestRecordPermission() else {
                failure = String(localized: "Allow microphone access in Settings to dictate reminders.", bundle: .app, locale: .app)
                return
            }
            guard let recognizer = VoiceRecognizer.recognizer(for: locale), recognizer.isAvailable else {
                failure = String(localized: "Speech recognition is not available for this language yet.", bundle: .app, locale: .app)
                return
            }
            do {
                try begin(with: recognizer, hints: hints)
            } catch {
                failure = String(localized: "Could not start the microphone.", bundle: .app, locale: .app)
                stop()
            }
        }
    }

    @MainActor
    func finish() async -> String {
        guard listening else { return transcript }
        stopEngine()
        request?.endAudio()
        for _ in 0..<15 where task != nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        stop()
        return transcript
    }

    func stop() {
        stopEngine()
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        listening = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    @MainActor
    static var available: Bool {
        Remote.shared.isOn(.voice) && supports(AppLanguage.current.locale)
    }

    @MainActor private static var support: [String: Bool] = [:]

    @MainActor
    private static func supports(_ locale: Locale) -> Bool {
        if let known = support[locale.identifier] {
            return known
        }
        let found = recognizer(for: locale) != nil
        support[locale.identifier] = found
        return found
    }

    private static func recognizer(for locale: Locale) -> SFSpeechRecognizer? {
        if let exact = SFSpeechRecognizer(locale: locale) {
            return exact
        }
        let language = locale.language.languageCode?.identifier
        let similar = SFSpeechRecognizer.supportedLocales().first { $0.language.languageCode?.identifier == language }
        return similar.flatMap(SFSpeechRecognizer.init(locale:))
    }

    private func begin(with recognizer: SFSpeechRecognizer, hints: [String]) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = hints
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let loudness = VoiceRecognizer.rms(buffer)
            DispatchQueue.main.async {
                guard let self, self.listening else { return }
                let speed = loudness > self.level ? 0.55 : 0.12
                self.level += (loudness - self.level) * speed
            }
        }
        engine.prepare()
        try engine.start()
        listening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if result?.isFinal == true {
                    self.task = nil
                } else if error != nil {
                    self.task = nil
                    if self.listening {
                        self.stop()
                    }
                }
            }
        }
    }

    private func stopEngine() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            sum += data[index] * data[index]
        }
        let value = Double(sqrt(sum / Float(count)))
        return min(1, value * 12)
    }
}
