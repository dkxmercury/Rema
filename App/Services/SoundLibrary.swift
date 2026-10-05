import AVFoundation
import Foundation
import RemaCore

enum SoundLibrary {
    private static let version = 1
    private static let versionKey = "sounds.version"

    static var folder: URL {
        SoundPlayer.librarySounds
    }

    static func url(_ event: Feedback.Event) -> URL {
        folder.appendingPathComponent("ui-\(event.rawValue).caf")
    }

    static func prepare() {
        DispatchQueue.global(qos: .utility).async {
            let manager = FileManager.default
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let current = UserDefaults.standard.integer(forKey: versionKey) == version
            for sound in BuiltInSound.allCases {
                guard let name = sound.fileName else { continue }
                let target = folder.appendingPathComponent(name)
                if current, manager.fileExists(atPath: target.path) { continue }
                write(Synth.notification(sound), to: target)
            }
            for event in Feedback.Event.allCases {
                let target = url(event)
                if current, manager.fileExists(atPath: target.path) { continue }
                write(Synth.interface(event), to: target)
            }
            UserDefaults.standard.set(version, forKey: versionKey)
        }
    }

    private static func write(_ samples: [Float], to target: URL) {
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: Synth.rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Synth.rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        try? FileManager.default.removeItem(at: target)
        guard let file = try? AVAudioFile(forWriting: target, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false) else { return }
        try? file.write(from: buffer)
    }
}

enum Synth {
    static let rate = 44_100.0

    private static let barModes: [Double] = [1, 2.756, 5.404, 8.933]

    static func notification(_ sound: BuiltInSound) -> [Float] {
        switch sound {
        case .mechanika:
            var track = Track(seconds: 1.9)
            track.noise(at: 0, length: 0.006, gain: 0.5, center: 3_500)
            track.noise(at: 0.045, length: 0.006, gain: 0.4, center: 3_100)
            track.bell(at: 0.1, frequency: 1_760, gain: 0.8, decay: 0.45, weights: [1, 0.35, 0.12])
            track.bell(at: 0.55, frequency: 1_760, gain: 0.6, decay: 0.45, weights: [1, 0.35, 0.12])
            return track.normalized(peak: 0.85)
        case .bell:
            var track = Track(seconds: 2.6)
            track.bell(at: 0, frequency: 1_318.5, gain: 0.9, decay: 0.9, weights: [1, 0.45, 0.2, 0.08])
            track.bell(at: 0.28, frequency: 1_975.5, gain: 0.7, decay: 0.8, weights: [1, 0.4, 0.15, 0.05])
            return track.normalized(peak: 0.85)
        case .drops:
            var track = Track(seconds: 1.1)
            for (start, pitch) in [(0.0, 700.0), (0.17, 950.0), (0.29, 820.0), (0.52, 1_100.0)] {
                track.tone(at: start, frequency: pitch, glideTo: pitch * 2.2, glide: 0.035, gain: 0.8, attack: 0.001, decay: 0.05, harmonics: [(1, 1), (2, 0.12)])
            }
            return track.normalized(peak: 0.85)
        case .ticktock:
            var track = Track(seconds: 1.5)
            for step in 0..<6 {
                let start = Double(step) * 0.24
                let tick = step.isMultiple(of: 2)
                track.noise(at: start, length: 0.005, gain: 0.6, center: tick ? 4_200 : 2_000)
                track.tone(at: start, frequency: tick ? 2_800 : 1_400, gain: 0.35, attack: 0.0005, decay: tick ? 0.01 : 0.014)
            }
            return track.normalized(peak: 0.8)
        case .soft:
            var track = Track(seconds: 2.2)
            track.tone(at: 0, frequency: 1_046.5, gain: 0.7, attack: 0.025, decay: 0.7, harmonics: [(1, 1), (2, 0.15)])
            track.tone(at: 0.22, frequency: 1_568, gain: 0.6, attack: 0.025, decay: 0.7, harmonics: [(1, 1), (2, 0.12)])
            return track.normalized(peak: 0.6)
        case .silent:
            return []
        }
    }

    static func interface(_ event: Feedback.Event) -> [Float] {
        var track = Track(seconds: 0.2)
        switch event {
        case .check:
            track.tone(at: 0, frequency: 1_400, gain: 0.8, attack: 0.001, decay: 0.012)
            track.tone(at: 0.045, frequency: 2_100, gain: 0.8, attack: 0.001, decay: 0.015)
        case .uncheck:
            track.tone(at: 0, frequency: 900, glideTo: 700, glide: 0.04, gain: 0.8, attack: 0.001, decay: 0.02)
        case .toggle:
            track.noise(at: 0, length: 0.003, gain: 1, center: 3_000)
            track.tone(at: 0, frequency: 520, gain: 0.5, attack: 0.0005, decay: 0.01)
        case .select:
            track.noise(at: 0, length: 0.002, gain: 0.6, center: 5_000, q: 0.9)
        case .delete:
            track.tone(at: 0, frequency: 420, glideTo: 180, glide: 0.09, gain: 0.9, attack: 0.002, decay: 0.05)
        case .save:
            track.tone(at: 0, frequency: 990, glideTo: 660, glide: 0.015, gain: 0.8, attack: 0.001, decay: 0.04)
        case .error:
            track.tone(at: 0, frequency: 320, gain: 0.9, attack: 0.002, decay: 0.03)
            track.tone(at: 0.09, frequency: 320, gain: 0.9, attack: 0.002, decay: 0.03)
        }
        return track.normalized(peak: 0.22)
    }

    private struct Track {
        var samples: [Float]
        private var seed: UInt32 = 0x1234_5678

        init(seconds: Double) {
            samples = Array(repeating: 0, count: Int(seconds * Synth.rate))
        }

        mutating func tone(at start: Double, frequency: Double, glideTo target: Double? = nil, glide: Double = 0, gain: Double, attack: Double, decay: Double, harmonics: [(Double, Double)] = [(1, 1)]) {
            let first = Int(start * Synth.rate)
            let length = Int((attack + decay * 7) * Synth.rate)
            var phase = 0.0
            for index in 0..<length where first + index < samples.count {
                let time = Double(index) / Synth.rate
                var pitch = frequency
                if let target, glide > 0 {
                    pitch = frequency * pow(target / frequency, min(time / glide, 1))
                }
                phase += 2 * .pi * pitch / Synth.rate
                let rise = attack > 0 ? min(time / attack, 1) : 1
                let envelope = rise * exp(-max(time - attack, 0) / decay)
                var value = 0.0
                for (ratio, weight) in harmonics {
                    value += weight * sin(phase * ratio)
                }
                samples[first + index] += Float(gain * envelope * value)
            }
        }

        mutating func bell(at start: Double, frequency: Double, gain: Double, decay: Double, weights: [Double]) {
            for (index, weight) in weights.enumerated() where index < Synth.barModes.count {
                let ratio = Synth.barModes[index]
                tone(at: start, frequency: frequency * ratio, gain: gain * weight, attack: 0.002, decay: decay / sqrt(ratio))
            }
        }

        mutating func noise(at start: Double, length: Double, gain: Double, center: Double, q: Double = 1.5) {
            let first = Int(start * Synth.rate)
            let count = Int(length * 4 * Synth.rate)
            let omega = 2 * .pi * center / Synth.rate
            let alpha = sin(omega) / (2 * q)
            let a0 = 1 + alpha
            let b0 = alpha / a0
            let b2 = -alpha / a0
            let a1 = -2 * cos(omega) / a0
            let a2 = (1 - alpha) / a0
            var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
            for index in 0..<count where first + index < samples.count {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let input = Double(seed) / Double(UInt32.max) * 2 - 1
                let output = b0 * input + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1
                x1 = input
                y2 = y1
                y1 = output
                let time = Double(index) / Synth.rate
                let envelope = min(time / 0.0005, 1) * exp(-time / (length / 2))
                samples[first + index] += Float(gain * envelope * output * 3)
            }
        }

        func normalized(peak target: Float) -> [Float] {
            let peak = samples.map(abs).max() ?? 0
            guard peak > 0 else { return samples }
            let scale = target / peak
            let fade = min(Int(0.005 * Synth.rate), samples.count)
            return samples.enumerated().map { index, value in
                let tail = samples.count - index
                let edge: Float = tail < fade ? Float(tail) / Float(fade) : 1
                return value * scale * edge
            }
        }
    }
}
