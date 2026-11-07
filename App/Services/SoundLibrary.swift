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
            for event in Feedback.Event.allCases {
                let target = url(event)
                if current, manager.fileExists(atPath: target.path) { continue }
                write(Synth.interface(event), to: target)
            }
            for sound in BuiltInSound.allCases {
                guard let name = sound.fileName else { continue }
                let target = folder.appendingPathComponent(name)
                if current, manager.fileExists(atPath: target.path) { continue }
                write(Synth.notification(sound), to: target)
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
    private static let marimbaBar: [(Double, Double)] = [(1, 1), (3.99, 0.22), (9.9, 0.06)]
    private static let kalimbaTine: [(Double, Double)] = [(1, 1), (5.95, 0.12), (2, 0.05)]
    private static let warm: [(Double, Double)] = [(1, 1), (2, 0.2)]
    private static let comb: [(Double, Double)] = [(1, 1), (3, 0.12), (5.2, 0.08), (7.1, 0.04)]
    private static let plucked: [(Double, Double)] = [(1, 1), (2, 0.3), (3, 0.15)]

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
        case .marimba:
            var track = Track(seconds: 1.8)
            for (start, name) in [(0.0, "C6"), (0.12, "E6"), (0.24, "G6")] {
                track.tone(at: start, frequency: note(name), gain: 0.8, attack: 0.001, decay: 0.18, harmonics: marimbaBar)
            }
            track.tone(at: 0.45, frequency: note("C7"), gain: 0.7, attack: 0.001, decay: 0.3, harmonics: marimbaBar)
            return track.normalized(peak: 0.85)
        case .kalimba:
            var track = Track(seconds: 2.4)
            for (start, name) in [(0.0, "D6"), (0.15, "A5"), (0.3, "F#6"), (0.5, "E6")] {
                track.tone(at: start, frequency: note(name), gain: 0.8, attack: 0.002, decay: 0.35, harmonics: kalimbaTine)
            }
            return track.normalized(peak: 0.8)
        case .crystal:
            var track = Track(seconds: 4.5)
            for (start, name) in [(0.0, "C7"), (0.11, "G7"), (0.22, "E7")] {
                track.bell(at: start, frequency: note(name), gain: 0.7, decay: 1.4, weights: [1, 0.3, 0.1])
            }
            return track.normalized(peak: 0.75)
        case .bubbles:
            var track = Track(seconds: 1.2)
            for (start, low) in [(0.0, 420.0), (0.08, 520.0), (0.14, 470.0), (0.24, 610.0), (0.3, 700.0), (0.42, 820.0)] {
                track.tone(at: start, frequency: low, glideTo: low * 2.6, glide: 0.06, gain: 0.7, attack: 0.002, decay: 0.07, harmonics: [(1, 1), (2, 0.08)])
            }
            return track.normalized(peak: 0.8)
        case .wood:
            var track = Track(seconds: 1.4)
            for start in [0.0, 0.16] {
                track.noise(at: start, length: 0.004, gain: 0.5, center: 1_800, q: 2.5)
                track.tone(at: start, frequency: 820, gain: 0.6, attack: 0.0005, decay: 0.03)
            }
            track.tone(at: 0.42, frequency: note("G4"), gain: 0.7, attack: 0.001, decay: 0.25, harmonics: marimbaBar)
            return track.normalized(peak: 0.85)
        case .morning:
            var track = Track(seconds: 3.2)
            for (start, name) in [(0.0, "C5"), (0.18, "E5"), (0.36, "G5"), (0.54, "C6")] {
                track.tone(at: start, frequency: note(name), gain: 0.6, attack: 0.03, decay: 0.6, harmonics: warm)
            }
            return track.normalized(peak: 0.6)
        case .musicbox:
            let tune: [(String, Double)] = [
                ("E6", 1), ("G6", 1), ("C7", 1), ("B6", 1), ("A6", 1), ("G6", 1), ("E6", 2),
                ("F6", 1), ("A6", 1), ("G6", 1), ("E6", 1), ("D6", 2), ("C6", 2),
                ("E6", 1), ("G6", 1), ("C7", 1), ("D7", 1), ("E7", 1), ("D7", 1), ("C7", 2),
                ("A6", 1), ("B6", 1), ("G6", 1), ("E6", 1), ("D6", 1), ("E6", 1), ("C6", 2),
            ]
            let bass = ["C4", "G3", "A3", "F3", "C4", "G3", "F3", "G3"]
            let beat = 0.3
            var track = Track(seconds: tune.reduce(0.0) { $0 + $1.1 } * beat + 2.2)
            var time = 0.0
            for (index, (name, beats)) in tune.enumerated() {
                track.tone(at: time, frequency: note(name), gain: 0.7, attack: 0.001, decay: 0.5, harmonics: comb)
                if index.isMultiple(of: 4) {
                    track.tone(at: time, frequency: note(bass[(index / 4) % bass.count]), gain: 0.32, attack: 0.002, decay: 0.8, harmonics: comb)
                }
                time += beats * beat
            }
            track.tone(at: time, frequency: note("C4"), gain: 0.32, attack: 0.002, decay: 1, harmonics: comb)
            track.tone(at: time, frequency: note("C6"), gain: 0.6, attack: 0.001, decay: 0.7, harmonics: comb)
            return track.normalized(peak: 0.8)
        case .sunrise:
            var track = Track(seconds: 20)
            let chords: [(start: Double, notes: [String], attack: Double, decay: Double, gain: Double)] = [
                (0, ["C4", "G4", "E5"], 3, 2.6, 0.35),
                (6.5, ["F4", "A4", "C5"], 2.5, 2.2, 0.35),
                (12, ["G4", "D5", "B4"], 2, 2, 0.4),
            ]
            for chord in chords {
                for name in chord.notes {
                    track.tone(at: chord.start, frequency: note(name), gain: chord.gain, attack: chord.attack, decay: chord.decay, harmonics: warm)
                }
            }
            let scale = ["C6", "D6", "E6", "G6", "A6", "C7"]
            let strikes = [3.5, 5, 6.2, 7.3, 8.2, 9, 9.7, 10.4, 11, 11.6, 12.2, 12.7, 13.2, 13.7, 14.2, 14.6, 15, 15.4, 15.8, 16.2]
            for (index, start) in strikes.enumerated() {
                let gain = 0.2 + 0.6 * Double(index) / Double(strikes.count - 1)
                track.bell(at: start, frequency: note(scale[(index * 3) % scale.count]), gain: gain, decay: 1.2, weights: [1, 0.35, 0.12])
            }
            return track.normalized(peak: 0.8)
        case .chimes:
            var track = Track(seconds: 16)
            let strikes: [(Double, String, Double)] = [
                (0, "E6", 0.78), (0.586, "C6", 0.43), (1.291, "E6", 0.63), (2.314, "D6", 0.41), (2.933, "C6", 0.5),
                (3.651, "C6", 0.73), (4.007, "D6", 0.65), (4.752, "C6", 0.63), (5.339, "D6", 0.42), (6.319, "E6", 0.57),
                (7.029, "A6", 0.52), (7.972, "D6", 0.44), (8.708, "D6", 0.55), (9.423, "C6", 0.63), (10.2, "G6", 0.67),
                (10.813, "E6", 0.59), (11.848, "E6", 0.52), (12.773, "C7", 0.71), (13.093, "E6", 0.61),
            ]
            for (start, name, gain) in strikes {
                track.bell(at: start, frequency: note(name), gain: gain, decay: 1.6, weights: [1, 0.4, 0.15])
            }
            return track.normalized(peak: 0.75)
        case .harp:
            let chords = [
                ["C4", "E4", "G4", "C5", "E5", "G5", "C6"],
                ["F3", "A3", "C4", "F4", "A4", "C5", "F5"],
                ["G3", "B3", "D4", "G4", "B4", "D5", "G5"],
                ["C4", "E4", "G4", "C5", "E5", "G5", "C6", "E6"],
            ]
            var track = Track(seconds: 13.5)
            for (index, chord) in chords.enumerated() {
                for (step, name) in chord.enumerated() {
                    track.tone(at: Double(index) * 3 + Double(step) * 0.07, frequency: note(name), gain: 0.55, attack: 0.003, decay: 0.9, harmonics: plucked)
                }
            }
            return track.normalized(peak: 0.8)
        case .rising:
            var track = Track(seconds: 20)
            let rounds = 15
            for pass in 0..<rounds {
                let gain = 0.15 + 0.85 * Double(pass) / Double(rounds - 1)
                for (offset, name) in [(0.0, "G5"), (0.18, "C6"), (0.36, "E6")] {
                    track.bell(at: Double(pass) * 1.25 + offset, frequency: note(name), gain: gain, decay: 0.5, weights: [1, 0.3])
                }
            }
            return track.normalized(peak: 0.85)
        case .silent:
            return []
        }
    }

    private static func note(_ name: String) -> Double {
        let steps: [Character: Int] = ["C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2]
        var octave = name.dropFirst()
        var sharp = 0
        if octave.first == "#" {
            sharp = 1
            octave = octave.dropFirst()
        }
        let semitones = (name.first.flatMap { steps[$0] } ?? 0) + sharp + ((Int(octave) ?? 4) - 4) * 12
        return 440 * pow(2, Double(semitones) / 12)
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
            let length = min(Int((attack + decay * 7) * Synth.rate), samples.count - first)
            guard length > 0 else { return }
            var phase = 0.0
            for index in 0..<length {
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
            for index in 0..<max(0, min(count, samples.count - first)) {
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
