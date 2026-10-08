import XCTest

// Each test plays one scene of the app at a calm pace for a video. The screen is recorded outside the test,
// the printed marks tell where the scene begins and ends.
final class Scenes: XCTestCase {
    private let language = ProcessInfo.processInfo.environment["DEMO_LANGUAGE"] ?? "ru"

    private var english: Bool {
        language == "en"
    }

    override func setUp() {
        continueAfterFailure = true
    }

    func testPhrase() {
        let app = launch("phrase")
        compose(app)
        type(english ? "call mom at 6 pm" : "в 6 вечера позвонить маме", into: app)
        pause(2.5)
        app.typeText("\n")
        pause(3)
        mark("END")
    }

    func testRepeat() {
        let app = launch("repeat")
        compose(app)
        type(english ? "yoga every Tue and Thu at 8" : "каждый вт и чт в 8 йога", into: app)
        pause(3)
        app.typeText("\n")
        pause(2)
        mark("END")
    }

    func testList() {
        let app = launch("list")
        compose(app)
        type(english ? "buy bread, milk and eggs tonight" : "вечером купить хлеб, молоко и яйца", into: app)
        pause(3)
        app.typeText("\n")
        pause(1.5)
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", english ? "Buy bread, milk" : "Купить хлеб, молоко")).firstMatch
        if row.waitForExistence(timeout: 5) {
            row.tap()
            pause(1.5)
            for item in english ? ["bread", "milk"] : ["хлеб", "молоко"] {
                let line = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", item)).firstMatch
                if line.waitForExistence(timeout: 3) {
                    line.tap()
                    pause(1)
                }
            }
            pause(1.5)
        }
        mark("END")
    }

    func testCalendar() {
        let app = launch("calendar")
        pause(1.5)
        let button = app.buttons[english ? "Calendar" : "Календарь"]
        if button.waitForExistence(timeout: 5) {
            button.tap()
            pause(2.5)
            app.swipeLeft()
            pause(2)
            app.swipeRight()
            pause(2)
            let close = app.buttons[english ? "Close" : "Закрыть"].firstMatch
            if close.exists {
                close.tap()
                pause(1.5)
            }
        }
        mark("END")
    }

    func testFriends() {
        let app = launch("friends")
        pause(1)
        let open = app.buttons[english ? "Open" : "Открыть"].firstMatch
        if open.waitForExistence(timeout: 5) {
            open.tap()
            pause(2)
            let accept = app.buttons[english ? "Accept" : "Принять"].firstMatch
            if accept.waitForExistence(timeout: 5) {
                accept.tap()
                pause(1.5)
            }
            let close = app.buttons[english ? "Close" : "Закрыть"].firstMatch
            if close.exists {
                close.tap()
                pause(1.5)
            }
        }
        compose(app)
        type(english ? "movie on Friday at 8 pm" : "в пятницу в 20 кино", into: app)
        pause(1)
        // The chips sit under the keyboard; it goes down the way a person would push it.
        app.swipeDown()
        pause(1)
        let share = app.buttons[english ? "With friends" : "С друзьями"].firstMatch
        if share.waitForExistence(timeout: 5) {
            share.tap()
            pause(1)
            for name in english ? ["Anna", "Ilya"] : ["Аня", "Илья"] {
                let chip = app.buttons[name].firstMatch
                if chip.waitForExistence(timeout: 3) {
                    chip.tap()
                    pause(0.7)
                }
            }
            pause(1)
            let send = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", english ? "Send to" : "Отправить")).firstMatch
            if send.waitForExistence(timeout: 3) {
                send.tap()
                pause(3)
            }
        }
        mark("END")
    }

    private func launch(_ scene: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-RemaDemo", language, "-RemaDemoScene", scene]
        if let zone = ProcessInfo.processInfo.environment["DEMO_TZ"] {
            app.launchEnvironment["TZ"] = zone
        }
        app.launch()
        _ = app.buttons[english ? "New reminder" : "Новое напоминание"].waitForExistence(timeout: 30)
        pause(1)
        mark("START")
        pause(1.5)
        return app
    }

    private func compose(_ app: XCUIApplication) {
        app.buttons[english ? "New reminder" : "Новое напоминание"].firstMatch.tap()
        pause(1.2)
    }

    private func type(_ text: String, into app: XCUIApplication) {
        for character in text {
            app.typeText(String(character))
            Thread.sleep(forTimeInterval: character == " " ? 0.12 : 0.06)
        }
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func mark(_ name: String) {
        print("SCENE-\(name) \(Date().timeIntervalSince1970)")
    }
}
