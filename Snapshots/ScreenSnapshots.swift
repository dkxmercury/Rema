import SnapshotTesting
import SwiftUI
import XCTest
@testable import Rema

final class ScreenSnapshots: XCTestCase {
    func testHome() throws {
        try render(HomeScreen(content: .sample), name: "D-Home", style: .light)
        try render(HomeScreen(content: .sample), name: "D-Home-Dark", style: .dark)
    }

    private func render<Screen: View>(_ screen: Screen, name: String, style: UIUserInterfaceStyle) throws {
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
