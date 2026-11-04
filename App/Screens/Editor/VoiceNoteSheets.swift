import RemaCore
import SwiftUI

struct LevelBars: View {
    let levels: [Float]
    var played: Int?
    var height: CGFloat = 56

    var body: some View {
        let shown = Array(repeating: Float(0), count: max(0, VoiceRecorder.bars - levels.count)) + levels.suffix(VoiceRecorder.bars)
        HStack(spacing: 4) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, level in
                Capsule()
                    .fill(played.map { index < $0 } ?? true ? Palette.accent : Palette.secondary.opacity(0.35))
                    .frame(width: 4, height: max(6, height * CGFloat(level)))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.1), value: shown)
        .accessibilityHidden(true)
    }
}

struct VoiceRecordSheet: View {
    let title: String
    var shared = false
    @State var recorder: VoiceRecorder
    let onDone: (TimeInterval?) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voice note")
                        .font(.app(.jost, 26, weight: 500))
                    Text(verbatim: title)
                        .font(.app(.golos, 14))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 28)
                switch recorder.phase {
                case .denied, .failed:
                    problem
                default:
                    recording
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 100)
            Button(action: cancel) {
                Text("Cancel")
            }
            .buttonStyle(RaisedButtonStyle())
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .foregroundStyle(Palette.text)
        .task {
            if recorder.phase == .starting {
                await recorder.start()
            }
        }
        .onChange(of: recorder.phase) { _, phase in
            if phase == .finished {
                finish()
            }
        }
    }

    private var recording: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(verbatim: recorder.elapsed.clock)
                    .font(.app(.jost, 56, weight: 500))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("of \(CustomSound.maximumSeconds.clock)")
                    .font(.app(.golos, 14))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.top, 26)
            LevelBars(levels: recorder.levels, height: 64)
                .padding(.top, 22)
            Button(action: finish) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 76, height: 76)
                        RoundedRectangle(cornerRadius: 5, style: .circular)
                            .fill(Palette.onAccent)
                            .frame(width: 24, height: 24)
                    }
                    Text("Stop")
                        .font(.app(.golos, 14, weight: 600))
                }
            }
            .buttonStyle(PressableStyle())
            .disabled(recorder.phase != .recording)
            .padding(.top, 28)
            Text(shared ? "Everyone in the reminder will hear the note. It plays instead of the sound when the reminder comes." : "The note plays instead of the sound when the reminder comes. You can also listen to it in the reminder itself.")
                .font(.app(.golos, 13))
                .lineHeight(18, .golos, 13)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.top, 22)
        }
    }

    private var problem: some View {
        VStack(spacing: 14) {
            Text(recorder.phase == .denied ? "Allow microphone access in Settings to record a voice note." : "Could not start the microphone.")
                .font(.app(.golos, 15))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if recorder.phase == .denied, let settings = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { openURL(settings) }
                    .buttonStyle(SmallButtonStyle(prominent: true, height: 44))
                    .fixedSize()
            }
        }
        .padding(.top, 40)
    }

    private func finish() {
        Feedback.play(.save)
        onDone(recorder.stop())
    }

    private func cancel() {
        recorder.discard()
        onDone(nil)
    }
}

struct VoicePlayerSheet: View {
    let reminder: Reminder
    let note: CustomSound
    let occurrence: Date
    var now: Date = Date()
    var calendar: Calendar = .current
    var locale: Locale = AppLanguage.current.locale
    var levels: [Float]?
    let onSnooze: () -> Void
    let onDone: () -> Void
    @State private var player = VoicePlayer.shared

    private var shape: [Float] {
        levels ?? VoiceShape.levels(of: note)
    }

    private var playing: Bool {
        player.playing == note.id && !player.paused
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: reminder.title)
                        .font(.app(.jost, 26, weight: 500))
                        .lineLimit(2)
                    Text(verbatim: subtitle)
                        .font(.app(.golos, 14))
                        .foregroundStyle(Palette.secondary)
                }
                .padding(.top, 28)
                VStack(spacing: 14) {
                    LevelBars(levels: shape, played: player.playing == note.id ? Int((player.progress * Double(VoiceRecorder.bars)).rounded()) : nil)
                    HStack {
                        Text(verbatim: (player.playing == note.id ? player.current : 0).clock)
                        Spacer()
                        Button {
                            player.toggle(note)
                        } label: {
                            ZStack {
                                RaisedCircle(size: 64)
                                Glyph(paths: playing ? Icons.pause : Icons.play, size: 24, lineWidth: 3.2, color: Palette.text, filled: !playing)
                            }
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel(Text(playing ? LocalizedStringKey("Pause") : LocalizedStringKey("Listen")))
                        Spacer()
                        Text(verbatim: note.duration.clock)
                    }
                    .font(.app(.jost, 15, weight: 500))
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondary)
                }
                .padding(.top, 18)
                .padding(.bottom, 16)
                .padding(.horizontal, 16)
                .panel()
                .padding(.top, 22)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            HStack(spacing: 10) {
                Button(action: onSnooze) {
                    Text("In 15 minutes")
                }
                .buttonStyle(RaisedButtonStyle())
                Button(action: onDone) {
                    Text("Done")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .foregroundStyle(Palette.text)
        .onAppear {
            if levels == nil {
                player.play(note)
            }
        }
        .onDisappear {
            player.stop()
        }
    }

    private var subtitle: String {
        let when = Describer(calendar: calendar, locale: locale).dayAndTime(occurrence, now: now).capitalizedFirst(locale)
        return "\(when), " + String(localized: "voice note", bundle: .app, locale: .app)
    }
}
