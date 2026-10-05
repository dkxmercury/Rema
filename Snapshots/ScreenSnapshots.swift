import SnapshotTesting
import SwiftUI
import XCTest
@testable import Rema

final class ScreenSnapshots: XCTestCase {
    func testHome() throws {
        try render(HomeScreen(content: SampleData.home), name: "D-Home", style: .light)
        try render(HomeScreen(content: SampleData.home), name: "D-Home-Dark", style: .dark)
    }

    func testSafeAreaProbe() throws {
        try render(SafeAreaProbe(), name: "Probe", style: .light)
    }

    func testEditor() throws {
        let store = sampleStore()
        for (name, style) in [("D-Editor", UIUserInterfaceStyle.light), ("D-Editor-Dark", .dark)] {
            try render(EditorScreen(draft: SampleData.server, isNew: false, store: store, now: SampleData.now, calendar: SampleData.calendar, locale: russian, onClose: {}), name: name, style: style)
        }
    }

    func testDateTime() throws {
        let initial = SampleData.calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 10, minute: 0))!
        try render(DateTimeScreen(initial: initial, now: SampleData.now, settings: .standard(at: SampleData.now), calendar: SampleData.calendar, locale: russian, onDone: { _ in }, onClose: {}), name: "D-DateTime", style: .light)
    }

    func testRepeat() throws {
        try render(RepeatScreen(draft: .constant(SampleData.server), now: SampleData.now, calendar: SampleData.calendar, locale: russian, onBack: {}), name: "D-Repeat", style: .light)
    }

    func testEarly() throws {
        try render(EarlyScreen(draft: .constant(SampleData.server), now: SampleData.now, calendar: SampleData.calendar, locale: russian, onBack: {}), name: "D-Before", style: .light)
    }

    func testPhrase() throws {
        try render(PhraseScreen(store: sampleStore(), text: "завтра в 9 позвонить маме", now: SampleData.now, calendar: SampleData.calendar, locale: russian, autofocus: false, onClose: {}), name: "D-Phrase", style: .light)
    }

    func testVoice() throws {
        let recognizer = VoiceRecognizer()
        recognizer.transcript = "напомни в пятницу вечером забрать костюм из химчистки"
        recognizer.listening = true
        try render(VoiceScreen(store: sampleStore(), now: SampleData.now, calendar: SampleData.calendar, locale: russian, recognizer: recognizer, live: false, onFinish: { _ in }), name: "D-Voice", style: .light)
    }

    private var russian: Locale { Locale(identifier: "ru_RU") }

    private func sampleStore() -> Store {
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        store.seed(reminders: SampleData.reminders, places: SampleData.places, sounds: [SampleData.gong])
        return store
    }
}

private struct SafeAreaProbe: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.red).frame(height: 4)
            Spacer(minLength: 0)
            Rectangle().fill(Color.blue).frame(height: 4)
        }
        .background(Color.white.ignoresSafeArea())
    }
}

private extension ScreenSnapshots {
    func render<Screen: View>(_ screen: Screen, name: String, style: UIUserInterfaceStyle) throws {
        guard let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else {
            throw XCTSkip("SNAPSHOT_DIR не задан")
        }
        let view = AnyView(
            screen
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .environment(\.colorScheme, style == .dark ? .dark : .light)
        )
        let strategy = Snapshotting<AnyView, UIImage>.image(
            layout: .device(config: .iPhone13),
            traits: UITraitCollection(userInterfaceStyle: style)
        )
        let finished = expectation(description: name)
        var output: UIImage?
        strategy.snapshot(view).run { image in
            output = image
            finished.fulfill()
        }
        wait(for: [finished], timeout: 60)
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try XCTUnwrap(output?.pngData()).write(to: url)
    }
}
