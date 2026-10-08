import XCTest

// Each test plays one scene of the app at a calm pace for a video. The screen is recorded outside the test.
// The printed marks tell the edit what happened when, and where on the screen: taps, typing, the new reminder.
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
        // A time counted from now stays today whatever hour the recording runs at, so the new reminder shows on the dial.
        type(english ? "call mom in 2 hours" : "через 2 часа позвонить маме", into: app)
        pause(2.5)
        save(app)
        reveal(app, english ? "Call mom" : "Позвонить маме")
        finish()
    }

    func testRepeat() {
        let app = launch("repeat")
        compose(app)
        type(english ? "yoga every Tue and Thu at 8" : "каждый вт и чт в 8 йога", into: app)
        pause(1)
        let chip = app.buttons[english ? "Repeat" : "Повтор"].firstMatch
        if chip.waitForExistence(timeout: 3) {
            mark("CHIP", chip)
        }
        pause(2.5)
        save(app)
        // The reminder comes next Tuesday, so it is shown where every coming reminder is.
        let scheduled = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", english ? "All scheduled" : "Все запланированные")).firstMatch
        if scheduled.waitForExistence(timeout: 5) {
            tap(scheduled, "OPEN")
            pause(1.5)
            reveal(app, english ? "Yoga" : "Йога")
        } else {
            tree(app, "scheduled")
        }
        finish()
    }

    func testList() {
        let app = launch("list")
        compose(app)
        type(english ? "buy bread, milk and eggs tonight" : "вечером купить хлеб, молоко и яйца", into: app)
        pause(1)
        let card = app.staticTexts[english ? "Make a list?" : "Составить список?"].firstMatch
        if card.waitForExistence(timeout: 3) {
            mark("CARD", card)
        }
        pause(2.5)
        save(app)
        if let row = reveal(app, english ? "Buy bread, milk" : "Купить хлеб, молоко") {
            tap(row, "ROW")
            pause(2)
            // The tick is the round button before the name; the name itself does not react.
            for item in english ? ["Bread", "Milk"] : ["Хлеб", "Молоко"] {
                let box = app.buttons[item].firstMatch
                if box.waitForExistence(timeout: 3) {
                    tap(box, "TICK")
                    pause(1.2)
                }
            }
            mark("TICKED")
            pause(2)
        }
        finish()
    }

    func testCalendar() {
        let app = launch("calendar")
        pause(1.5)
        let button = app.buttons[english ? "Calendar" : "Календарь"].firstMatch
        if button.waitForExistence(timeout: 5) {
            tap(button, "CALENDAR")
            pause(3)
            // The buttons, not a swipe: a swipe from the edge closes the calendar.
            let steps = english
                ? [("Next month", "NEXT"), ("Previous month", "PREVIOUS"), ("Week", "WEEK")]
                : [("Следующий месяц", "NEXT"), ("Предыдущий месяц", "PREVIOUS"), ("Неделя", "WEEK")]
            for (label, name) in steps {
                let control = app.buttons[label].firstMatch
                if control.waitForExistence(timeout: 3) {
                    tap(control, name)
                    pause(2.2)
                }
            }
            pause(1)
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
            tap(open, "INVITATION")
            pause(2.5)
            let accept = app.buttons[english ? "Accept" : "Принять"].firstMatch
            if accept.waitForExistence(timeout: 5) {
                tap(accept, "ACCEPT")
                pause(2)
            }
            let close = app.buttons[english ? "Close" : "Закрыть"].firstMatch
            if close.exists {
                tap(close, "CLOSE")
                pause(1.5)
            }
        } else {
            tree(app, "invitation")
        }
        compose(app)
        type(english ? "movie at 10 pm" : "в 22 кино", into: app)
        pause(1)
        let share = app.buttons[english ? "With friends" : "С друзьями"].firstMatch
        if share.waitForExistence(timeout: 5) {
            tap(share, "SHARE")
            pause(1.2)
            // The friends come up under the keyboard; the screen is pushed up a little, the keyboard stays.
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            pause(1)
            for name in english ? ["Anna", "Ilya"] : ["Аня", "Илья"] {
                let chip = app.buttons[name].firstMatch
                if chip.waitForExistence(timeout: 3) {
                    tap(chip, "FRIEND")
                    pause(0.8)
                }
            }
            pause(1)
            let send = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", english ? "Send to" : "Отправить")).firstMatch
            if send.waitForExistence(timeout: 3), send.isHittable {
                mark("SAVE")
                tap(send, "SEND")
            } else {
                app.textViews.firstMatch.tap()
                save(app)
            }
            pause(1)
            reveal(app, english ? "Movie" : "Кино")
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
        mark("WINDOW", app.windows.firstMatch)
        pause(1)
        handshake()
        mark("START")
        pause(1.5)
        return app
    }

    // The first keyboard of a fresh simulator shows a tour of swipe typing; it is seen and closed before the recording.
    private func warmUp(_ app: XCUIApplication) {
        app.buttons[english ? "New reminder" : "Новое напоминание"].firstMatch.tap()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 10)
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
        tap(app.buttons[english ? "New reminder" : "Новое напоминание"].firstMatch, "COMPOSE")
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

    // The return key confirms the reminder; it sits on the keyboard, so the mark carries no place.
    private func save(_ app: XCUIApplication) {
        mark("SAVE")
        app.typeText("\n")
    }

    // The new reminder, found by the start of its title, is marked with its place for the highlight.
    @discardableResult
    private func reveal(_ app: XCUIApplication, _ title: String) -> XCUIElement? {
        let element = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", title)).firstMatch
        guard element.waitForExistence(timeout: 8) else {
            tree(app, "new reminder")
            return nil
        }
        pause(0.4)
        mark("NEW", element)
        pause(2.8)
        return element
    }

    private func tap(_ element: XCUIElement, _ name: String) {
        mark(name, element)
        element.tap()
    }

    private func finish() {
        pause(1)
        mark("END")
    }

    // The recording starts only when the app is up and warmed, so the launch never gets into the video;
    // the scene says it is ready and waits for the word that the recording runs.
    private func handshake() {
        guard let sync = ProcessInfo.processInfo.environment["DEMO_SYNC"] else { return }
        let folder = URL(fileURLWithPath: sync)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("ready").path, contents: Data())
        let go = folder.appendingPathComponent("go").path
        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: go), Date() < deadline {
            pause(0.1)
        }
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func mark(_ name: String, _ element: XCUIElement? = nil) {
        var line = "SCENE-MARK \(name) \(Date().timeIntervalSince1970)"
        if let element, element.exists {
            let frame = element.frame
            line += " \(frame.minX) \(frame.minY) \(frame.width) \(frame.height)"
        }
        print(line)
    }

    private func tree(_ app: XCUIApplication, _ place: String) {
        print("SCENE-TREE \(place)")
        print(app.debugDescription)
    }
}
