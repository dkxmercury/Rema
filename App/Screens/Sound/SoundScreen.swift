import AVFoundation
import RemaCore
import SwiftUI
import UniformTypeIdentifiers

struct SoundScreen: View {
    let store: Store
    @Binding var choice: SoundChoice
    var locale: Locale = .current
    let onBack: () -> Void

    @State private var importing = false
    @State private var failed = false
    @State private var working = false

    private var describer: Describer {
        Describer(calendar: .current, locale: locale)
    }

    private var effective: SoundChoice {
        SoundPlayer.resolve(choice, settings: store.settings)
    }

    private var customSounds: [CustomSound] {
        store.sounds.filter { $0.deletedAt == nil }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(title: "Sound", leading: .back, action: onBack)
                    SectionLabel(text: "Built-in")
                        .padding(.top, 16)
                    PanelList {
                        ForEach(Array(BuiltInSound.allCases.enumerated()), id: \.element) { index, sound in
                            let last = index == BuiltInSound.allCases.count - 1
                            row(
                                title: describer.builtInName(sound),
                                selected: effective == .builtIn(sound.rawValue),
                                height: 50,
                                duration: nil,
                                playable: sound != .silent,
                                choice: .builtIn(sound.rawValue)
                            )
                            if !last {
                                Hairline()
                            }
                        }
                    }
                    .padding(.top, 8)
                    SectionLabel(text: "Your own")
                        .padding(.top, 18)
                    PanelList {
                        ForEach(customSounds) { sound in
                            row(title: sound.name, selected: effective == .custom(sound.id), height: 52, duration: sound.duration, playable: true, choice: .custom(sound.id))
                                .contextMenu {
                                    Button(role: .destructive) {
                                        remove(sound)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            Hairline()
                        }
                        Button {
                            importing = true
                        } label: {
                            HStack(spacing: 12) {
                                if working {
                                    ProgressView()
                                        .frame(width: 20, height: 20)
                                } else {
                                    Glyph(paths: Icons.folder, size: 20, lineWidth: 2, color: Palette.accentText)
                                }
                                Text("Choose from Files")
                                    .font(.app(.golos, 16, weight: 600))
                                    .foregroundStyle(Palette.accentText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .disabled(working)
                    }
                    .padding(.top, 8)
                    Text("mp3, m4a or wav will do. Files longer than 30 seconds are trimmed, iOS requires it.")
                        .font(.app(.golos, 13))
                        .lineHeight(18, .golos, 13)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, 15)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            PrimaryBar(action: onBack) {
                Text("Done")
            }
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: customSounds)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            guard case .success(let url) = result else { return }
            load(url)
        }
        .alert("Could not read this file", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func row(title: String, selected: Bool, height: CGFloat, duration: Double?, playable: Bool, choice option: SoundChoice) -> some View {
        HStack(spacing: 8) {
            Button {
                choice = option
                Feedback.play(.select)
                if playable {
                    SoundPlayer.preview(option, settings: store.settings, sounds: store.sounds)
                }
            } label: {
                HStack(spacing: 12) {
                    RadioMark(isOn: selected)
                    Text(verbatim: title)
                        .font(.app(.golos, 16, weight: selected ? 600 : 400))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let duration {
                        Text(verbatim: String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60))
                            .font(.app(.jost, 14, weight: 500))
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityAddTraits(selected ? .isSelected : [])
            if playable {
                Button {
                    SoundPlayer.preview(option, settings: store.settings, sounds: store.sounds)
                } label: {
                    ZStack {
                        RaisedCircle(size: 30)
                        Glyph(paths: Icons.play, size: 12, color: Palette.text, filled: true)
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(PressableStyle())
                .padding(.trailing, -8)
                .accessibilityLabel(Text("Play: \(title)"))
            }
        }
        .frame(minHeight: height)
    }

    private func load(_ url: URL) {
        working = true
        Task.detached(priority: .userInitiated) {
            let sound = try? SoundImporter.importFile(at: url)
            await MainActor.run {
                working = false
                guard let sound else {
                    failed = true
                    Feedback.play(.error)
                    return
                }
                store.save(sound)
                choice = .custom(sound.id)
                Feedback.play(.save)
            }
        }
    }

    private func remove(_ sound: CustomSound) {
        var deleted = sound
        deleted.deletedAt = Date()
        store.save(deleted)
        if effective == .custom(sound.id) {
            choice = .standard
        }
        try? FileManager.default.removeItem(at: SoundLibrary.folder.appendingPathComponent(sound.fileName))
        Feedback.play(.delete)
    }
}

enum SoundImporter {
    struct Unreadable: Error {}

    static func importFile(at url: URL) throws -> CustomSound {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let limit = AVAudioFramePosition(format.sampleRate * CustomSound.maximumSeconds)
        let frames = AVAudioFrameCount(min(input.length, limit))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw Unreadable() }
        try input.read(into: buffer, frameCount: frames)
        if input.length > limit {
            fadeOut(buffer, seconds: 0.5)
        }
        let sound = CustomSound(name: url.lastPathComponent, duration: Double(buffer.frameLength) / format.sampleRate, createdAt: Date())
        try FileManager.default.createDirectory(at: SoundLibrary.folder, withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let target = SoundLibrary.folder.appendingPathComponent(sound.fileName)
        let output = try AVAudioFile(forWriting: target, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        try output.write(from: buffer)
        return sound
    }

    private static func fadeOut(_ buffer: AVAudioPCMBuffer, seconds: Double) {
        guard let channels = buffer.floatChannelData else { return }
        let length = Int(buffer.frameLength)
        let fade = min(length, Int(buffer.format.sampleRate * seconds))
        for channel in 0..<Int(buffer.format.channelCount) {
            for index in 0..<fade {
                let position = length - fade + index
                channels[channel][position] *= Float(fade - index) / Float(fade)
            }
        }
    }
}
