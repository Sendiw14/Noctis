import XCTest

/// Onboarding step 1, the goals (APP_RULES.md R6): at most two chosen, Continue only with one, Skip, nothing clipped at the default size and at the
/// largest text, on the iPhone 17 Pro and the iPhone SE.
@MainActor
final class GoalQATests: XCTestCase {
    private func goal(extra: [String] = [], goals: String? = nil) -> XCUIApplication {
        let app = QA.launch(step: "goal", goals: goals, extra: extra)
        XCTAssertTrue(app.buttons["goal.continue"].waitForExistence(timeout: 12), "the goals step is on screen")
        return app
    }

    private func tile(_ app: XCUIApplication, _ goal: String) -> XCUIElement { app.descendants(matching: .any)["goal.\(goal)"] }

    func testAtMostTwoAreChosenAndAThirdChangesNothing() {
        let app = goal()
        QA.pause(1.5)
        XCTAssertFalse(app.buttons["goal.continue"].isEnabled, "Continue waits for a goal")
        tile(app, "betterSleep").tap()
        XCTAssertTrue(app.buttons["goal.continue"].isEnabled, "one goal is enough")
        tile(app, "moreEnergy").tap()
        QA.pause(0.6)
        QA.shot("goal-two-chosen")
        tile(app, "betterRecovery").tap()
        QA.pause(0.2)
        QA.shot("goal-limit")
        XCTAssertTrue(tile(app, "betterSleep").isSelected && tile(app, "moreEnergy").isSelected, "the first two stay chosen")
        XCTAssertFalse(tile(app, "betterRecovery").isSelected, "the third is not chosen")
        XCTAssertTrue(app.staticTexts["Pick up to two."].waitForExistence(timeout: 2), "the limit is said")
        // Letting one go makes room.
        tile(app, "betterSleep").tap()
        tile(app, "betterRecovery").tap()
        XCTAssertTrue(tile(app, "betterRecovery").isSelected)
    }

    func testContinueGoesOnAndSkipGoesOn() {
        let app = goal(goals: "betterSleep")
        QA.pause(1)
        XCTAssertTrue(app.buttons["goal.continue"].isEnabled)
        app.buttons["goal.continue"].tap()
        XCTAssertTrue(QA.element(app, labelBeginsWith: "Wake time").waitForExistence(timeout: 6), "Rhythm follows")
        let skipped = goal()
        skipped.buttons["goal.skip"].tap()
        XCTAssertTrue(QA.element(skipped, labelBeginsWith: "Wake time").waitForExistence(timeout: 6), "Skip goes on too")
    }

    private func assertFits(_ app: XCUIApplication, scrolls: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        let continueButton = app.buttons["goal.continue"], skip = app.buttons["goal.skip"]
        XCTAssertTrue(continueButton.isHittable && skip.isHittable, "both actions are tappable", file: file, line: line)
        XCTAssertGreaterThanOrEqual(skip.frame.minY, continueButton.frame.maxY - 0.5, "the actions do not overlap", file: file, line: line)
        XCTAssertLessThanOrEqual(skip.frame.maxY, window.maxY + 0.5, file: file, line: line)
        for goal in ["betterSleep", "moreEnergy", "betterRecovery", "betterConsistency", "betterFocus"] {
            let frame = tile(app, goal).frame
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "\(goal) is inside the screen", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "\(goal) is inside the screen", file: file, line: line)
            if !scrolls {
                XCTAssertTrue(tile(app, goal).isHittable, "\(goal) is whole and tappable at rest", file: file, line: line)
                XCTAssertLessThanOrEqual(frame.maxY, continueButton.frame.minY + 0.5, "\(goal) is not under the Continue button", file: file, line: line)
            }
        }
    }

    func testNothingIsClippedAtTheDefaultSize() {
        let app = goal()
        QA.pause(2)
        assertFits(app, scrolls: false)
        QA.shot("goal-default")
    }

    func testNothingIsClippedAtTheLargestText() {
        let app = goal(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        QA.pause(2)
        assertFits(app, scrolls: true)
        // The last tile is reachable by scrolling.
        QA.tap(tile(app, "betterFocus"), in: app)
        XCTAssertTrue(tile(app, "betterFocus").isSelected)
        QA.shot("goal-xxxl")
    }
}
