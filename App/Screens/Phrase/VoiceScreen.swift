import RemaCore
import SwiftUI

struct VoiceScreen: View {
    let store: Store
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let live: Bool
    let onFinish: (String?) -> Void

    @State private var recognizer: VoiceRecognizer
    @State private var finishing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: Store, now: Date = Date(), calendar: Calendar = .current, locale: Locale = AppLanguage.current.locale, recognizer: VoiceRecognizer = VoiceRecognizer(), live: Bool = true, onFinish: @escaping (String?) -> Void) {
        self.store = store
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.live = live
        self.onFinish = onFinish
        _recognizer = State(initialValue: recognizer)
    }

    private var parsed: ParsedPhrase {
        PhraseParser(now: now, calendar: calendar, morning: store.settings.morning, evening: store.settings.evening, places: store.activePlaces.map(\.name), preferred: AppLanguage.current.rawValue).parse(recognizer.transcript)
    }

    private var describer: Describer {
        Describer(calendar: calendar, locale: locale)
    }

    private var when: Date? {
        guard let schedule = parsed.schedule else { return nil }
        return Recurrence.next(schedule, after: now.addingTimeInterval(-60), limit: 1, calendar: calendar).first
    }

    private var place: String? {
        parsed.placeNames.first
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ScreenHeader(title: "Speak", leading: .close) {
                    recognizer.stop()
                    onFinish(nil)
                }
                transcript
                    .padding(.top, 14)
                if when != nil || place != nil {
                    ReminderPreview(when: when, place: place, summary: parsed.title.lowercased(with: locale), describer: describer, calendar: calendar)
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .offset(y: -8)))
                }
                if let failure = recognizer.failure {
                    Text(verbatim: failure)
                        .font(.app(.golos, 15))
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 15)

            microphone
                .padding(.bottom, 54)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: parsed.highlights)
        .animation(Motion.standard, value: when)
        .animation(Motion.fade, value: recognizer.failure)
        .onAppear {
            if live {
                listen()
            }
        }
        .onDisappear { recognizer.stop() }
        .task(id: recognizer.transcript) {
            guard live, recognizer.listening, !recognizer.transcript.isEmpty else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, recognizer.listening else { return }
            await finish()
        }
    }

    private func listen() {
        recognizer.start(locale: locale, hints: store.activePlaces.map(\.name))
    }

    private func finish() async {
        guard !finishing else { return }
        finishing = true
        Feedback.play(.select)
        let spoken = await recognizer.finish()
        onFinish(spoken)
    }

    private var pendingWord: Range<Int>? {
        guard recognizer.listening else { return nil }
        let characters = Array(recognizer.transcript)
        guard let end = characters.lastIndex(where: { !$0.isWhitespace }) else { return nil }
        var start = end
        while start > 0, !characters[start - 1].isWhitespace {
            start -= 1
        }
        let word = start..<(end + 1)
        return parsed.highlights.contains { $0.overlaps(word) } ? nil : word
    }

    private var transcript: some View {
        PhraseField(text: .constant(recognizer.transcript), highlights: parsed.highlights, pending: pendingWord, editable: false)
            .overlay(alignment: .topLeading) {
                if recognizer.transcript.isEmpty {
                    Text("For example, remind me tomorrow at 9 to call mom")
                        .font(.app(.golos, 24, weight: 600))
                        .foregroundStyle(Palette.faint)
                        .lineSpacing(3)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 64, alignment: .topLeading)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .accessibilityElement(children: .combine)
    }

    private var animated: Bool {
        live && !reduceMotion
    }

    private var microphone: some View {
        TimelineView(.animation(paused: !animated || !recognizer.listening)) { timeline in
            let breath = animated && recognizer.listening ? (sin(timeline.date.timeIntervalSinceReferenceDate * .pi / 0.8) + 1) / 2 : 0
            let level = animated ? recognizer.level : 0
            ZStack {
                Circle()
                    .strokeBorder(Palette.accent.opacity(0.12), lineWidth: 2)
                    .frame(width: 200, height: 200)
                    .scaleEffect(1 + breath * 0.035 + level * 0.12)
                Circle()
                    .strokeBorder(Palette.accent.opacity(0.25), lineWidth: 2)
                    .frame(width: 144, height: 144)
                    .scaleEffect(1 + breath * 0.025 + level * 0.09)
                micButton
            }
            .frame(width: 200, height: 200)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 4) {
                if recognizer.failure == nil {
                    Text("Listening…")
                        .font(.app(.golos, 15, weight: 600))
                    Text("Tap to finish")
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                } else {
                    Text("Tap to try again")
                        .font(.app(.golos, 15, weight: 600))
                }
            }
            .fixedSize()
            .alignmentGuide(.bottom) { $0[.top] + 16 }
        }
    }

    private var micButton: some View {
        Button {
            if recognizer.failure != nil {
                Feedback.play(.select)
                listen()
            } else {
                Task { await finish() }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Palette.accent.shadow(.drop(color: Palette.accent.opacity(0.35), radius: 12, x: 0, y: 10)))
                    .insetShadow(Circle(), .black.opacity(0.15), y: -3)
                Glyph(paths: Icons.microphone, size: 34, lineWidth: 2.1, color: Palette.onAccent)
            }
            .frame(width: 88, height: 88)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text("Finish"))
    }
}
