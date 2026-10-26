import XCTest

/// Onboarding step 2, the rhythm (APP_RULES.md R6): both rulers are adjustable (VoiceOver's swipe moves them by a fixed step), the bedtime follows them,
/// and nothing is clipped or under the Continue button at the default size and at the largest text, on the iPhone 17 Pro and the iPhone SE.
@MainActor
final class RhythmQATests: XCTestCase {
    private func rhythm(extra: [String] = []) -> XCUIApplication {
        let app = QA.launch(step: "rhythm", goals: "betterSleep", extra: extra)
        XCTAssertTrue(app.buttons["rhythm.continue"].waitForExistence(timeout: 12), "the rhythm step is on screen")
        return app
    }

    private func ruler(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.sliders[id] }

    private func plain(_ value: Any?) -> String {
        (value as? String ?? "").replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    func testBothRulersAreAdjustableAndTheBedtimeFollows() {
        let app = rhythm()
        QA.pause(2)
        let wake = ruler(app, "rhythm.wake"), need = ruler(app, "rhythm.need")
        XCTAssertTrue(wake.waitForExistence(timeout: 4), "the wake ruler is an adjustable element")
        XCTAssertTrue(need.exists, "the sleep need ruler is an adjustable element")
        XCTAssertEqual(plain(wake.value), "7:00 AM")
        XCTAssertEqual(plain(need.value), "8 hours")
        let bedtime = app.descendants(matching: .any)["rhythm.bedtime"]
        XCTAssertTrue(plain(bedtime.label).contains("11:00 PM"), "the bedtime for 7:00 AM and 8 hours")
        // The ruler is dragged (VoiceOver's own step, 15 and 30 minutes, is held by RhythmStepTests): the value and the bedtime follow.
        let from = wake.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)), to = wake.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to)
        XCTAssertNotEqual(plain(wake.value), "7:00 AM", "the wake time moved")
        XCTAssertFalse(plain(bedtime.label).contains("11:00 PM"), "the bedtime followed")
    }

    private func assertFits(_ app: XCUIApplication, scrolls: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        let next = app.buttons["rhythm.continue"]
        XCTAssertTrue(next.isHittable, "Continue is tappable", file: file, line: line)
        XCTAssertLessThanOrEqual(next.frame.maxY, window.maxY + 0.5, file: file, line: line)
        for id in ["rhythm.wake", "rhythm.need"] {
            let frame = ruler(app, id).frame
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "\(id) is inside the screen", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, file: file, line: line)
            if !scrolls { XCTAssertLessThanOrEqual(frame.maxY, next.frame.minY + 0.5, "\(id) is not under Continue", file: file, line: line) }
        }
        let bedtime = app.descendants(matching: .any)["rhythm.bedtime"].frame
        if !scrolls { XCTAssertLessThanOrEqual(bedtime.maxY, next.frame.minY + 0.5, "the bedtime card is not under Continue", file: file, line: line) }
    }

    func testNothingIsClippedAtTheDefaultSize() {
        let app = rhythm()
        QA.pause(2)
        assertFits(app, scrolls: false)
        QA.shot("rhythm-default")
    }

    func testNothingIsClippedAtTheLargestText() {
        let app = rhythm(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        QA.pause(2)
        assertFits(app, scrolls: true)
        QA.shot("rhythm-xxxl")
    }

    func testContinueGoesOn() {
        let app = rhythm()
        QA.pause(1.5)
        app.buttons["rhythm.continue"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Sample night")).firstMatch.waitForExistence(timeout: 8),
            "the Sample step follows")
    }
}
