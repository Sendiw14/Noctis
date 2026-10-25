import XCTest

/// Onboarding step 5, Stay gently informed (APP_RULES.md R6, R13): the example stack (tap for the next), three switches that are on, "Not now" goes on and
/// leaves everything off, and nothing is clipped at the default size and at the largest text, on the iPhone 17 Pro and the iPhone SE.
@MainActor
final class NotificationsQATests: XCTestCase {
    private func notifications(extra: [String] = []) -> XCUIApplication {
        let app = QA.launch(step: "notifications", goals: "betterSleep", extra: ["-useMockHealth"] + extra)
        XCTAssertTrue(app.buttons["notifications.allow"].waitForExistence(timeout: 12), "the Notifications step is on screen")
        return app
    }

    private func toggle(_ app: XCUIApplication, _ index: Int) -> XCUIElement { app.switches["notifications.toggle.\(index)"] }
    private func example(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["notifications.example"] }

    func testThreeSwitchesAreOnAndEachHasItsLine() {
        let app = notifications()
        QA.pause(1.5)
        for (index, words) in [(0, "Morning summary. Your night and recovery, ready when you wake"), (1, "Wind-down reminder. 20 minutes before your bedtime"), (2, "Weekly review. A calm look back, once a week")] {
            let row = toggle(app, index)
            XCTAssertTrue(row.exists, "switch \(index)")
            XCTAssertEqual(row.label, words)
            XCTAssertEqual(row.value as? String, "1", "on by default")
        }
    }

    func testASwitchTurnsOffAndOnAgainAndTheExampleTurnsToIt() {
        let app = notifications()
        QA.pause(1.5)
        flip(app, 1)
        XCTAssertEqual(toggle(app, 1).value as? String, "0")
        XCTAssertEqual(example(app).label, "Example notification: your wind-down starts in 20 minutes", "the example turns to the reminder that was changed")
        flip(app, 1)
        XCTAssertEqual(toggle(app, 1).value as? String, "1")
    }

    /// The row is one element for VoiceOver (title, line and switch); a touch goes to the switch at its right end.
    private func flip(_ app: XCUIApplication, _ index: Int) {
        toggle(app, index).coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        QA.pause(0.5)
    }

    func testOneAndThenAllThreeSwitchesOffAreShownOff() {
        let app = notifications()
        QA.pause(1.5)
        flip(app, 0)
        QA.pause(0.4)
        QA.shot("notifications-one-off")
        flip(app, 1)
        flip(app, 2)
        QA.pause(0.6)
        QA.shot("notifications-all-off")
        for index in 0..<3 { XCTAssertEqual(toggle(app, index).value as? String, "0", "switch \(index) is off") }
        XCTAssertTrue(app.buttons["notifications.allow"].isHittable, "Allow is still there with everything off: the person may turn them on in Settings later")
    }

    func testTappingTheExampleCyclesThroughTheThree() {
        let app = notifications()
        QA.pause(1.5)
        XCTAssertEqual(example(app).label, "Example notification: your morning summary is ready")
        example(app).tap()
        QA.pause(0.4)
        XCTAssertEqual(example(app).label, "Example notification: your wind-down starts in 20 minutes")
        example(app).tap()
        QA.pause(0.4)
        XCTAssertEqual(example(app).label, "Example notification: your weekly review is ready")
        example(app).tap()
        QA.pause(0.4)
        XCTAssertEqual(example(app).label, "Example notification: your morning summary is ready", "round again")
    }

    func testNotNowGoesOnWithoutAsking() {
        let app = notifications()
        QA.pause(1)
        app.buttons["notifications.notNow"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["plan.row.0"].waitForExistence(timeout: 8), "the plan is being built")
    }

    func testBackGoesToHealth() {
        let app = notifications()
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["health.connect"].waitForExistence(timeout: 8))
    }

    private func assertFits(_ app: XCUIApplication, scrolls: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        let allow = app.buttons["notifications.allow"]
        XCTAssertTrue(allow.isHittable && app.buttons["notifications.notNow"].isHittable, "both buttons are tappable", file: file, line: line)
        for index in 0..<3 {
            let frame = toggle(app, index).frame
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "switch \(index) is inside the screen", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "switch \(index) is inside the screen", file: file, line: line)
            if !scrolls { XCTAssertLessThanOrEqual(frame.maxY, allow.frame.minY + 0.5, "switch \(index) is not under Allow", file: file, line: line) }
        }
        let stack = example(app).frame
        XCTAssertLessThanOrEqual(stack.maxX, window.maxX + 0.5, file: file, line: line)
        XCTAssertLessThanOrEqual(stack.maxY, toggle(app, 0).frame.minY + 0.5, "the example is above the switches", file: file, line: line)
    }

    func testNothingIsClippedAtTheDefaultSize() {
        let app = notifications()
        QA.pause(2)
        assertFits(app, scrolls: false)
        QA.shot("notifications-default")
    }

    func testNothingIsClippedAtTheLargestText() {
        let app = notifications(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        QA.pause(2)
        assertFits(app, scrolls: true)
        QA.shot("notifications-xxxl")
    }
}
