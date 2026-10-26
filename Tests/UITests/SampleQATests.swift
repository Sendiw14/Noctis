import XCTest

/// Onboarding step 3, the sample night (APP_RULES.md R6, R13): the ring and four tiles, a tile highlights its stage and a second tap clears it, nothing is
/// clipped at the default size and at the largest text, on the iPhone 17 Pro and the iPhone SE. Always labelled as a sample.
@MainActor
final class SampleQATests: XCTestCase {
    private func sample(extra: [String] = []) -> XCUIApplication {
        let app = QA.launch(step: "sample", goals: "betterSleep", extra: extra)
        XCTAssertTrue(app.buttons["sample.continue"].waitForExistence(timeout: 12), "the sample step is on screen")
        return app
    }

    private func tile(_ app: XCUIApplication, _ stage: String) -> XCUIElement { app.buttons["sample.tile.\(stage)"] }

    func testATileHighlightsItsStageAndASecondTapClearsIt() {
        let app = sample()
        QA.pause(2.5)
        XCTAssertTrue(app.staticTexts["SAMPLE"].exists || app.otherElements["SAMPLE"].exists, "the sample tag is there")
        XCTAssertTrue(app.staticTexts["Sample data. Your own night appears after your first sleep."].exists, "and the line under the tiles")
        let deep = tile(app, "deep")
        XCTAssertFalse(deep.isSelected)
        deep.tap()
        QA.pause(0.7)
        QA.shot("sample-tile-selected")
        XCTAssertTrue(deep.isSelected, "the first tap highlights it")
        XCTAssertFalse(tile(app, "core").isSelected, "only one at a time")
        tile(app, "core").tap()
        XCTAssertTrue(tile(app, "core").isSelected && !deep.isSelected, "another tile takes over")
        tile(app, "core").tap()
        XCTAssertFalse(tile(app, "core").isSelected, "a second tap clears it")
    }

    private func assertFits(_ app: XCUIApplication, scrolls: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        let next = app.buttons["sample.continue"]
        XCTAssertTrue(next.isHittable, "Continue is tappable", file: file, line: line)
        for stage in ["deep", "core", "rem", "awake"] {
            let frame = tile(app, stage).frame
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "\(stage) is inside the screen", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "\(stage) is inside the screen", file: file, line: line)
            if !scrolls { XCTAssertLessThanOrEqual(frame.maxY, next.frame.minY + 0.5, "\(stage) is not under Continue", file: file, line: line) }
        }
        let note = app.staticTexts["Sample data. Your own night appears after your first sleep."].frame
        if !scrolls { XCTAssertLessThanOrEqual(note.maxY, next.frame.minY + 0.5, "the note is not under Continue", file: file, line: line) }
        XCTAssertGreaterThanOrEqual(note.minY, tile(app, "deep").frame.maxY - 0.5, "the note is under the tiles", file: file, line: line)
    }

    func testNothingIsClippedAtTheDefaultSize() {
        let app = sample()
        QA.pause(2.5)
        assertFits(app, scrolls: false)
        QA.shot("sample-default")
    }

    func testNothingIsClippedAtTheLargestText() {
        let app = sample(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        QA.pause(2.5)
        assertFits(app, scrolls: true)
        QA.shot("sample-xxxl")
    }

    func testContinueGoesOn() {
        let app = sample()
        QA.pause(2)
        app.buttons["sample.continue"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Apple Health")).firstMatch.waitForExistence(timeout: 8),
            "the Health step follows")
    }
}
