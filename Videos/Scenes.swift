import XCTest

// Each test plays one scene of the app at a calm pace for a video. The screen is recorded outside the test,
// the printed marks tell where the scene begins and ends and where the typing goes, which the edit speeds up.
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
        finish()
    }

    func testRepeat() {
        let app = launch("repeat")
        compose(app)
        type(english ? "yoga every Tue and Thu at 8" : "каждый вт и чт в 8 йога", into: app)
        pause(3)
        app.typeText("\n")
        pause(2.5)
        finish()
    }

    func testList() {
        let app = launch("list")
        compose(app)
        type(english ? "buy bread, milk and eggs tonight" : "вечером купить хлеб, молоко и яйца", into: app)
        pause(3)
        app.typeText("\n")
        pause(2)
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", english ? "Buy bread, milk" : "Купить хлеб, молоко")).firstMatch
        if row.waitForExistence(timeout: 5) {
            row.tap()
            pause(2)
            // The tick is the round button before the name; the name itself does not react.
            for item in english ? ["Bread", "Milk"] : ["Хлеб", "Молоко"] {
                let box = app.buttons[item].firstMatch
                if box.waitForExistence(timeout: 3) {
                    box.tap()
                    pause(1.2)
                }
            }
            pause(2)
        } else {
            tree(app, "list row")
        }
        finish()
    }

    func testCalendar() {
        let app = launch("calendar")
        pause(1.5)
        let button = app.buttons[english ? "Calendar" : "Календарь"].firstMatch
        if button.waitForExistence(timeout: 5) {
            button.tap()
            pause(3)
            app.swipeLeft()
            pause(2.5)
            app.swipeRight()
            pause(2.5)
        } else {
            tree(app, "calendar")
        }
        finish()
    }

    func testFriends() {
        let app = launch("friends")
        pause(1)
        let open = app.buttons[english ? "Open" : "Открыть"].firstMatch
        if open.waitForExistence(timeout: 5) {
            open.tap()
            pause(2.5)
            let accept = app.buttons[english ? "Accept" : "Принять"].firstMatch
            if accept.waitForExistence(timeout: 5) {
                accept.tap()
                pause(2)
            }
            let close = app.buttons[english ? "Close" : "Закрыть"].firstMatch
            if close.exists {
                close.tap()
                pause(1.5)
            }
        } else {
            tree(app, "invitation")
        }
        compose(app)
        type(english ? "movie on Friday at 8 pm" : "в пятницу в 20 кино", into: app)
        pause(1)
        // The friends sit under the keyboard; it goes down the way a person would push it.
        app.scrollViews.firstMatch.swipeDown()
        pause(1.2)
        let share = app.buttons[english ? "With friends" : "С друзьями"].firstMatch
        if share.waitForExistence(timeout: 5) {
            share.tap()
            pause(1.2)
            for name in english ? ["Anna", "Ilya"] : ["Аня", "Илья"] {
                let chip = app.buttons[name].firstMatch
                if chip.waitForExistence(timeout: 3) {
                    chip.tap()
                    pause(0.8)
                }
            }
            pause(1)
            let send = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", english ? "Send to" : "Отправить")).firstMatch
            if send.waitForExistence(timeout: 3), send.isHittable {
                send.tap()
            } else {
                app.typeText("\n")
            }
            pause(3)
        } else {
            tree(app, "with friends")
        }
        finish()
    }

    private func launch(_ scene: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-RemaDemo", language, "-RemaDemoScene", scene]
        app.launch()
        let start = app.buttons[english ? "New reminder" : "Новое напоминание"]
        if !start.waitForExistence(timeout: 60) {
            tree(app, "launch")
        }
        warmUp(app)
        pause(1)
        mark("START")
        pause(1.5)
        return app
    }

    // The first keyboard of a fresh simulator shows a tour of swipe typing; it is seen and closed before the recording counts.
    private func warmUp(_ app: XCUIApplication) {
        compose(app)
        for label in ["Continue", "Продолжить"] {
            let button = app.buttons[label].firstMatch
            if button.waitForExistence(timeout: 2) {
                button.tap()
                pause(1)
            }
        }
        let close = app.buttons[english ? "Close" : "Закрыть"].firstMatch
        if close.waitForExistence(timeout: 3) {
            close.tap()
        }
        pause(1.5)
    }

    private func compose(_ app: XCUIApplication) {
        app.buttons[english ? "New reminder" : "Новое напоминание"].firstMatch.tap()
        // Letters sent while the keyboard is still coming up get lost.
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 10)
        pause(0.8)
    }

    // A few letters at a time: one by one the test is too slow, and the edit speeds this part up anyway.
    private func type(_ text: String, into app: XCUIApplication) {
        mark("TYPE")
        var rest = Substring(text)
        while !rest.isEmpty {
            let piece = rest.prefix(3)
            app.typeText(String(piece))
            rest = rest.dropFirst(piece.count)
        }
        mark("TYPED")
    }

    private func finish() {
        pause(1)
        mark("END")
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func mark(_ name: String) {
        print("SCENE-MARK \(name) \(Date().timeIntervalSince1970)")
    }

    private func tree(_ app: XCUIApplication, _ place: String) {
        print("SCENE-TREE \(place)")
        print(app.debugDescription)
    }
}
