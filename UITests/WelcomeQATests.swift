import XCTest

/// Welcome (APP_RULES.md R6, R69): nothing clipped or overlapping, both buttons there and tappable, at the default size and at the largest text, and
/// the final state with Reduce Motion. Run it on the iPhone 17 Pro and on the iPhone SE; the Reduce Motion check needs the device set to it
/// (`QA_REDUCE_MOTION=1`, as the QA matrix's configuration does), because XCUITest cannot toggle that setting.
@MainActor
final class WelcomeQATests: XCTestCase {
    private func welcome(extra: [String] = []) -> XCUIApplication {
        let app = QA.launch(step: "welcome", extra: extra)
        XCTAssertTrue(app.buttons["welcome.continue"].waitForExistence(timeout: 12), "Welcome is on screen")
        return app
    }

    private func assertFitsAndTappable(_ app: XCUIApplication, scrolls: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        let apple = app.buttons["welcome.apple"]
        let plain = app.buttons["welcome.continue"]
        XCTAssertTrue(apple.exists && plain.exists, "both buttons exist", file: file, line: line)
        if scrolls {
            // Large text: the page scrolls, and both buttons are reachable.
            for _ in 0..<6 where !(apple.isHittable && plain.isHittable) { app.swipeUp() }
        }
        XCTAssertTrue(apple.isHittable, "Continue with Apple is tappable", file: file, line: line)
        XCTAssertTrue(plain.isHittable, "Continue without an account is tappable", file: file, line: line)
        XCTAssertGreaterThanOrEqual(plain.frame.minY, apple.frame.maxY - 0.5, "the buttons do not overlap", file: file, line: line)
        XCTAssertGreaterThanOrEqual(apple.frame.minX, window.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(apple.frame.maxX, window.maxX, "no button runs off the screen", file: file, line: line)
        XCTAssertLessThanOrEqual(plain.frame.maxX, window.maxX, file: file, line: line)
        // The footer sits under the second button and inside the screen.
        let footer = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "By continuing you agree")).firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 3), "the footer is there", file: file, line: line)
        XCTAssertGreaterThanOrEqual(footer.frame.minY, plain.frame.maxY - 0.5, "the footer never overlaps the second button", file: file, line: line)
        if !scrolls { XCTAssertLessThanOrEqual(footer.frame.maxY, window.maxY + 0.5, "the footer is not cut by the screen's edge", file: file, line: line) }
    }

    func testFitsAtTheDefaultSize() {
        let app = welcome()
        QA.pause(2.5)
        assertFitsAndTappable(app, scrolls: false)
        // The four bands read as one header.
        XCTAssertTrue(app.staticTexts["Better nights. A brighter you."].exists || app.otherElements["Better nights. A brighter you."].exists, "the bands are one VoiceOver element")
        QA.shot("welcome-default")
    }

    func testFitsAtTheLargestText() {
        let app = welcome(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        QA.pause(2.5)
        assertFitsAndTappable(app, scrolls: true)
        QA.shot("welcome-xxxl")
    }

    func testTheSecondButtonGoesToTheNextStep() {
        let app = welcome()
        QA.pause(2.5)
        app.buttons["welcome.continue"].tap()
        XCTAssertTrue(QA.element(app, labelBeginsWith: "Better sleep").waitForExistence(timeout: 6), "Goal follows, with no account")
    }

    func testReduceMotionShowsTheFinalStateAtOnce() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["QA_REDUCE_MOTION"] == "1", "needs the device set to Reduce Motion")
        let app = QA.launch(step: "welcome")
        // No animation to wait for: the buttons are there and tappable straight away.
        XCTAssertTrue(app.buttons["welcome.apple"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["welcome.apple"].isHittable && app.buttons["welcome.continue"].isHittable)
        QA.shot("welcome-reduce-motion")
    }
}
