import AVFoundation
import CoreLocation
import RemaCore
import Speech
import SwiftUI
import UserNotifications

struct IntroScreen: View {
    let store: Store
    let onFinish: () -> Void
    var onFeatures: () -> Void = {}

    enum Access: Equatable {
        case unknown
        case allowed
        case denied
    }

    @State private var page = 0
    @State private var played: Set<Int> = []
    @State private var spoken = 0
    @State private var notifications = Access.unknown
    @State private var location = Access.unknown
    @State private var microphone = Access.unknown
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let now = Date()
    private let pages = 3

    var body: some View {
        GeometryReader { proxy in
            let art = min(340, max(220, proxy.size.height - 420))
            ZStack {
                Palette.background.ignoresSafeArea()
                TabView(selection: $page) {
                    writePage(art).tag(0)
                    voicePage(art).tag(1)
                    accessPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                controls
            }
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: page)
        .onAppear { play(0) }
        .onChange(of: page) { _, index in play(index) }
        .task { await refreshAccess() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshAccess() }
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < pages - 1 {
                    Button(action: onFinish) {
                        Text("Skip")
                            .font(.app(.golos, 15, weight: 600))
                            .foregroundStyle(Palette.secondary)
                            .padding(.horizontal, 2)
                            .frame(height: 44)
                    }
                    .buttonStyle(RowPressStyle())
                    .transition(.opacity)
                }
            }
            .frame(height: 44)
            .padding(.top, 15)
            Spacer(minLength: 0)
            dots
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 24)
            Button(action: advance) {
                Text(page < pages - 1 ? LocalizedStringKey("Next") : LocalizedStringKey("Start"))
                    .contentTransition(.opacity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<pages, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Palette.accent : Palette.text.opacity(0.2))
                    .frame(width: index == page ? 20 : 6, height: 6)
            }
        }
        .animation(Motion.small, value: page)
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(page + 1) of \(pages)"))
    }

    private func introPage<Art: View>(_ art: CGFloat, title: LocalizedStringKey, text: LocalizedStringKey, @ViewBuilder illustration: () -> Art) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            illustration()
                .frame(maxWidth: .infinity)
                .frame(height: art)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .circular))
                .panel(radius: 28)
                .accessibilityHidden(true)
            Text(title)
                .font(.app(.jost, 30, weight: 500))
                .padding(.top, 28)
            Text(text)
                .font(.app(.golos, 16))
                .lineSpacing(4)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 67)
    }

    private func writePage(_ art: CGFloat) -> some View {
        introPage(art, title: "Write the way you speak", text: "Rema finds the date, time, repeat and place in the phrase. You can write in eight languages.") {
            writeIllustration
        }
    }

    private func voicePage(_ art: CGFloat) -> some View {
        introPage(art, title: "Or say it out loud", text: "Hold the plus on the home screen and talk. Speech is recognized right on the phone.") {
            voiceIllustration
        }
    }

    private var bubble: some View {
        RoundedRectangle(cornerRadius: 18, style: .circular)
            .fill(Palette.raisedTop.shadow(.drop(color: .black.opacity(0.10), radius: 1, y: 1)).shadow(.drop(color: .black.opacity(0.08), radius: 8, y: 6)))
    }

    private var writeIllustration: some View {
        let example = String(localized: "tomorrow at 9 call mom")
        let parsed = PhraseParser(now: now, calendar: .current, morning: store.settings.morning, evening: store.settings.evening, preferred: AppLanguage.current.rawValue).parse(example)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        let fallback = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        let date = parsed.schedule.flatMap { Recurrence.next($0, after: now, limit: 1, calendar: .current).first } ?? fallback
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let describer = Describer(locale: AppLanguage.current.locale)
        let shown = played.contains(0)
        return VStack(spacing: 0) {
            PhraseField(text: .constant(example), highlights: shown ? parsed.highlights : [], editable: false, size: 20)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(bubble)
            Spacer(minLength: 6)
            VStack(spacing: 0) {
                Path { path in
                    path.move(to: CGPoint(x: 1, y: 0))
                    path.addLine(to: CGPoint(x: 1, y: 40))
                }
                .trim(from: 0, to: shown ? 1 : 0)
                .stroke(Palette.accent.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .frame(width: 2, height: 40)
                Glyph(paths: Icons.chevronDown, size: 16, lineWidth: 2, color: Palette.accent.opacity(0.8))
                    .opacity(shown ? 1 : 0)
                    .offset(y: -4)
            }
            Spacer(minLength: 6)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: describer.shortTime(date))
                        .font(.app(.jost, 40, weight: 500))
                    Text(verbatim: describer.dayTitle(date))
                        .font(.app(.golos, 14, weight: 600))
                    Text(verbatim: parsed.title.isEmpty ? example : parsed.title)
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MiniDial(hour: shown ? parts.hour ?? 9 : 0, minute: shown ? parts.minute ?? 0 : 0, size: 72)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(bubble)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    private var voiceIllustration: some View {
        let phrase = String(localized: "buy bread when I leave work")
        let words = phrase.split(separator: " ").map(String.init)
        let shown = played.contains(1)
        return ZStack {
            rings
            VStack(spacing: 0) {
                Text("Hold the plus")
                    .font(.app(.golos, 13, weight: 600))
                    .foregroundStyle(Palette.dialWindowText)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(Palette.dialWindow))
                    .padding(.top, 24)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Glyph(paths: Icons.microphone, size: 16, lineWidth: 2.2, color: Palette.accentText)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Palette.accent.opacity(0.14)))
                    recognized(words, count: shown ? spoken : 0)
                        .font(.app(.golos, 17, weight: 600))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(Motion.small, value: spoken)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(minHeight: 54)
                .background(bubble)
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
                .opacity(shown ? 1 : 0)
            }
        }
    }

    private func recognized(_ words: [String], count: Int) -> Text {
        let visible = Array(words.prefix(count))
        guard let last = visible.last else { return Text(verbatim: " ") }
        let head = visible.dropLast().joined(separator: " ")
        let tail = Text(verbatim: last).foregroundColor(Palette.faint)
        return head.isEmpty ? tail : Text(verbatim: head + " ") + tail
    }

    private var rings: some View {
        ZStack {
            if reduceMotion {
                ringShapes(1)
            } else {
                PhaseAnimator([0.94, 1.04]) { scale in
                    ringShapes(scale)
                } animation: { _ in
                    .easeInOut(duration: 1.3)
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .circular)
                    .fill(Palette.accent.shadow(.drop(color: Palette.accent.opacity(0.32), radius: 11, y: 10)))
                    .insetShadow(RoundedRectangle(cornerRadius: 22, style: .circular), .black.opacity(0.14), y: -4)
                Glyph(paths: Icons.plus, size: 34, lineWidth: 2.4, color: Palette.onAccent)
            }
            .frame(width: 76, height: 76)
            Circle()
                .fill(Palette.text.opacity(0.10))
                .overlay(Circle().strokeBorder(Palette.text.opacity(0.20), lineWidth: 1.5))
                .frame(width: 50, height: 50)
                .offset(x: 21, y: 17)
        }
        .offset(y: -20)
    }

    private func ringShapes(_ scale: CGFloat) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.accent.opacity(0.14), lineWidth: 2)
                .frame(width: 208, height: 208)
                .scaleEffect(scale)
            Circle()
                .fill(Palette.accent.opacity(0.08))
                .overlay(Circle().strokeBorder(Palette.accent.opacity(0.26), lineWidth: 2))
                .frame(width: 152, height: 152)
                .scaleEffect(2 - scale)
        }
    }

    private var accessPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("So nothing slips by")
                .font(.app(.jost, 30, weight: 500))
            Text("Rema asks only for what it needs. You can change this in the phone settings.")
                .font(.app(.golos, 16))
                .lineSpacing(4)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            PanelList {
                accessRow(Icons.bell, prominent: true, title: "Notifications", text: "arrive on time, urgent ones get through Do Not Disturb", state: notifications, action: askNotifications)
                Hairline()
                accessRow(Icons.pin, prominent: false, title: "Location", text: "for “when I arrive” and “when I leave”, only while you use the app", state: location, action: askLocation)
                Hairline()
                accessRow(Icons.microphone, prominent: false, title: "Microphone", text: "for voice input, speech is recognized on the phone", state: microphone, action: askMicrophone)
            }
            .padding(.top, 20)
            Button(action: onFeatures) {
                Text("What Rema can do")
                    .font(.app(.golos, 15, weight: 600))
                    .foregroundStyle(Palette.accentTextOnBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 67)
    }

    private func accessRow(_ icon: [String], prominent: Bool, title: LocalizedStringKey, text: LocalizedStringKey, state: Access, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            ZStack {
                let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
                if prominent {
                    shape
                        .fill(Palette.accent)
                        .insetShadow(shape, .black.opacity(0.14), y: -2)
                } else {
                    shape
                        .fill(LinearGradient(colors: [Palette.raisedTop, Palette.raisedBottom], startPoint: .top, endPoint: .bottom).shadow(.drop(color: Palette.raisedShadowNear, radius: 1, y: 1)))
                        .insetShadow(shape, Palette.raisedHighlight, y: 1)
                }
                Glyph(paths: icon, size: 20, lineWidth: 2, color: prominent ? Palette.onAccent : Palette.text)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(.golos, 16, weight: 600))
                Text(text)
                    .font(.app(.golos, 13))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            switch state {
            case .allowed:
                Glyph(paths: Icons.check, size: 18, lineWidth: 2.6, color: Palette.accentText)
                    .frame(width: 36, height: 36)
                    .accessibilityElement()
                    .accessibilityLabel(Text("Allowed"))
                    .transition(.scale.combined(with: .opacity))
            case .denied:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text("Settings")
                }
                .buttonStyle(SmallButtonStyle(prominent: false))
            case .unknown:
                Button(action: action) {
                    Text("Allow")
                }
                .buttonStyle(SmallButtonStyle(prominent: prominent))
            }
        }
        .padding(.vertical, 14)
        .animation(Motion.small, value: state)
    }

    private func play(_ index: Int) {
        guard !played.contains(index) else { return }
        if reduceMotion {
            played.insert(index)
            if index == 1 {
                spoken = Int.max
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(duration: 0.9, bounce: 0.2)) {
                _ = played.insert(index)
            }
            guard index == 1 else { return }
            Task { @MainActor in
                for count in 1...12 {
                    try? await Task.sleep(for: .milliseconds(220))
                    spoken = count
                }
            }
        }
    }

    private func advance() {
        if page < pages - 1 {
            withAnimation(Motion.standard) { page += 1 }
        } else {
            onFinish()
        }
    }

    private func askNotifications() {
        Task { @MainActor in
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAccess()
            await Notifier.shared.reschedule()
        }
    }

    private func askLocation() {
        Task { @MainActor in
            _ = await LocationService.shared.requestPermission()
            await refreshAccess()
        }
    }

    private func askMicrophone() {
        Task { @MainActor in
            let speech = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            if speech == .authorized {
                _ = await AVAudioApplication.requestRecordPermission()
            }
            await refreshAccess()
        }
    }

    @MainActor
    private func refreshAccess() async {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notifications = .allowed
        case .denied:
            notifications = .denied
        default:
            notifications = .unknown
        }
        switch LocationService.shared.status {
        case .authorizedAlways, .authorizedWhenInUse:
            location = .allowed
        case .denied, .restricted:
            location = .denied
        default:
            location = .unknown
        }
        let speech = SFSpeechRecognizer.authorizationStatus()
        let record = AVAudioApplication.shared.recordPermission
        if speech == .authorized, record == .granted {
            microphone = .allowed
        } else if speech == .denied || speech == .restricted || record == .denied {
            microphone = .denied
        } else {
            microphone = .unknown
        }
    }
}
