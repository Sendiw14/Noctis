import XCTest

/// Onboarding step 6, "Building your plan" and "Your plan is ready" (APP_RULES.md R6, R13): the three rows finish and the plan follows by itself, the rings
/// never reach the rows, the plan shows what was chosen (bedtime, wake, need, the goals as chips), and nothing is clipped at the default size and at the
/// largest text, on the iPhone 17 Pro and the iPhone SE.
@MainActor
final class PlanQATests: XCTestCase {
    private func plan(goals: String? = "betterFocus,betterConsistency", wake: Int = 420, need: Int = 480, extra: [String] = []) -> XCUIApplication {
        QA.launch(
            step: "plan", goals: goals,
            extra: ["-useMockHealth", "-noctis.onboarding.wakeMinutes", "\(wake)", "-noctis.onboarding.needMinutes", "\(need)"] + extra)
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func normal(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ") }

    // MARK: Building

    func testTheThreeRowsFinishAndThePlanFollows() {
        let app = plan()
        XCTAssertTrue(element(app, "plan.row.0").waitForExistence(timeout: 10), "the building screen is on show")
        XCTAssertFalse(app.buttons["Back"].exists, "the building screen has no back button (and no progress bar)")
        XCTAssertEqual(element(app, "plan.row.0").label, "Starting fresh. We'll learn your pattern as you sleep.", "no nights yet: the first line says so")
        XCTAssertEqual(element(app, "plan.row.1").label, "Finding your typical bedtime")
        XCTAssertEqual(element(app, "plan.row.2").label, "Setting your sleep need")
        XCTAssertTrue(app.buttons["plan.continue"].waitForExistence(timeout: 14), "the plan follows on its own")
    }

    func testRowsAreCompletedOneAfterAnother() {
        let app = plan(extra: ["-noctisPlanHold", "1"])
        XCTAssertTrue(element(app, "plan.row.0").waitForExistence(timeout: 10))
        let done = NSPredicate(format: "value == %@", "Completed")
        expectation(for: done, evaluatedWith: element(app, "plan.row.0"))
        waitForExpectations(timeout: 6)
        XCTAssertEqual(element(app, "plan.row.1").value as? String, "In progress", "the second is still going while the first is done")
        XCTAssertEqual(element(app, "plan.row.2").value as? String, "In progress")
    }

    /// The first row of pixels (from the top, down the middle of the screen, below the rows) that is the lavender of the biggest ring, in points.
    private func lavenderTop(below minY: CGFloat, in app: XCUIApplication) -> CGFloat? {
        guard let cgImage = XCUIScreen.main.screenshot().image.cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let context = CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scale = CGFloat(width) / app.windows.firstMatch.frame.width
        let x = width / 2
        for y in Int(minY * scale)..<height {
            let i = (y * width + x) * 4
            if abs(Int(pixels[i]) - 0xA0) < 14, abs(Int(pixels[i + 1]) - 0x8C) < 14, abs(Int(pixels[i + 2]) - 0xEB) < 14 { return CGFloat(y) / scale }
        }
        return nil
    }

    func testTheRingsDoNotReachTheRows() {
        let app = plan(extra: ["-noctisPlanHold", "3"])
        XCTAssertTrue(element(app, "plan.row.2").waitForExistence(timeout: 10))
        QA.pause(7)
        let last = element(app, "plan.row.2").frame
        let top = lavenderTop(below: last.minY, in: app)
        XCTAssertNotNil(top, "the sunrise is on screen")
        XCTAssertGreaterThan(top ?? 0, last.maxY + 8, "the biggest ring starts under the last row (\(top ?? 0) vs \(last.maxY))")
        QA.shot("plan-building-final")
    }

    // MARK: Ready

    private func ready(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["plan.continue"].waitForExistence(timeout: 16), "the plan is ready")
        QA.pause(1.5)
    }

    func testTheTilesShowTheChoices() {
        let app = plan()
        ready(app)
        XCTAssertEqual(normal(element(app, "plan.tile.bedtime").label), "Bedtime, 11:00 PM")
        XCTAssertEqual(normal(element(app, "plan.tile.wake").label), "Wake, 7:00 AM")
        XCTAssertEqual(element(app, "plan.tile.sleepneed").label, "Sleep need, 8 hours")
    }

    func testASevenAndAHalfHourNeedShowsItsMinutes() {
        let app = plan(wake: 420, need: 450)
        ready(app)
        XCTAssertEqual(element(app, "plan.tile.sleepneed").label, "Sleep need, 7 hours 30 minutes")
        XCTAssertEqual(normal(element(app, "plan.tile.bedtime").label), "Bedtime, 11:30 PM", "7:00 AM minus 7 h 30 m")
        QA.shot("plan-ready-7h30")
    }

    func testTheChipsFollowTwoGoalsChosen() {
        let app = plan(goals: "betterFocus,betterConsistency")
        ready(app)
        if !element(app, "plan.chip.betterFocus").exists { QA.write(app.debugDescription, to: "plan-chips-missing.txt") }
        XCTAssertTrue(element(app, "plan.chip.betterFocus").exists && element(app, "plan.chip.betterConsistency").exists)
        XCTAssertFalse(element(app, "plan.chip.betterSleep").exists)
        XCTAssertEqual(element(app, "plan.chip.betterFocus").label, "Focus, Clearer focus")
        QA.shot("plan-ready-two-goals")
    }

    func testTheChipsFollowOneGoalChosen() {
        let app = plan(goals: "moreEnergy")
        ready(app)
        XCTAssertTrue(element(app, "plan.chip.moreEnergy").exists)
        XCTAssertFalse(element(app, "plan.chip.betterFocus").exists)
    }

    func testNoGoalsChosenHidesTheRow() {
        let app = plan(goals: nil)
        ready(app)
        for goal in ["betterSleep", "moreEnergy", "betterRecovery", "betterConsistency", "betterFocus"] {
            XCTAssertFalse(element(app, "plan.chip.\(goal)").exists, goal)
        }
        XCTAssertFalse(app.staticTexts["FOCUS"].exists, "the caption goes with the chips")
        QA.shot("plan-ready-no-goals")
    }

    func testTheTimelineRowsReadAsDays() {
        let app = plan()
        ready(app)
        XCTAssertEqual(element(app, "plan.day.today").label, "Today, Tonight is your first night, read in the morning")
        XCTAssertEqual(element(app, "plan.day.day7").label, "Day 7, Your first weekly review")
        XCTAssertEqual(element(app, "plan.day.day14").label, "Day 14, Early patterns appear")
    }

    func testBackGoesToNotificationsAndContinueGoesOn() {
        let app = plan()
        ready(app)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["notifications.allow"].waitForExistence(timeout: 8))
    }

    private func assertFits(_ app: XCUIApplication, scrolls: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        let next = app.buttons["plan.continue"]
        XCTAssertTrue(next.isHittable, "Continue is tappable", file: file, line: line)
        for id in ["plan.tile.bedtime", "plan.tile.wake", "plan.tile.sleepneed"] {
            let frame = element(app, id).frame
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "\(id) is inside the screen", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "\(id) is inside the screen", file: file, line: line)
        }
        let tiles = ["plan.tile.bedtime", "plan.tile.wake", "plan.tile.sleepneed"].map { element(app, $0).frame }
        if !scrolls {
            // Three across, never overlapping, and every row clear of Continue.
            XCTAssertEqual(Set(tiles.map { Int($0.minY) }).count, 1, "the tiles stand in one row", file: file, line: line)
            for (a, b) in zip(tiles, tiles.dropFirst()) { XCTAssertLessThanOrEqual(a.maxX, b.minX + 0.5, "the tiles do not overlap", file: file, line: line) }
            for id in ["plan.day.today", "plan.day.day7", "plan.day.day14"] {
                XCTAssertLessThanOrEqual(element(app, id).frame.maxY, next.frame.minY + 0.5, "\(id) is not under Continue", file: file, line: line)
            }
        } else {
            for (a, b) in zip(tiles, tiles.dropFirst()) {
                XCTAssertLessThanOrEqual(a.maxY, b.minY + 0.5, "the tiles stack without overlap", file: file, line: line)
            }
        }
    }

    func testNothingIsClippedAtTheDefaultSize() {
        let app = plan()
        ready(app)
        assertFits(app, scrolls: false)
        QA.shot("plan-ready-default")
    }

    func testNothingIsClippedAtTheLargestText() {
        let app = plan(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        ready(app)
        assertFits(app, scrolls: true)
        QA.shot("plan-ready-xxxl")
    }
}
