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
