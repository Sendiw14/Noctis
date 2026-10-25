import XCTest

/// Onboarding step 4, Connect your signals (APP_RULES.md R6, R13): three signal cards and the read-only card, nothing clipped at the default size and at
/// the largest text on the iPhone 17 Pro and the iPhone SE, "Continue without Health data" goes on without asking, and the mock Health store answers
/// "Connect Apple Health" the way the system sheet does (it never says what was allowed), so the step moves on.
@MainActor
final class HealthQATests: XCTestCase {
    private func health(extra: [String] = []) -> XCUIApplication {
        let app = QA.launch(step: "health", goals: "betterSleep", extra: ["-useMockHealth"] + extra)
        XCTAssertTrue(app.buttons["health.connect"].waitForExistence(timeout: 12), "the Health step is on screen")
        return app
    }

    private let kinds = ["sleepAnalysis", "heartRate", "hrv"]

    private func card(_ app: XCUIApplication, _ kind: String) -> XCUIElement { app.descendants(matching: .any)["health.card.\(kind)"] }

    private func assertFits(_ app: XCUIApplication, scrolls: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        let connect = app.buttons["health.connect"]
        let skip = app.buttons["health.skip"]
        XCTAssertTrue(connect.isHittable && skip.isHittable, "both buttons are tappable", file: file, line: line)
        XCTAssertLessThan(connect.frame.maxY, skip.frame.minY + 1, "Connect is above Continue without", file: file, line: line)
        for kind in kinds + ["privacy"] {
            let frame = (kind == "privacy" ? app.descendants(matching: .any)["health.privacy"] : card(app, kind)).frame
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "\(kind) is inside the screen", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "\(kind) is inside the screen", file: file, line: line)
            if !scrolls { XCTAssertLessThanOrEqual(frame.maxY, connect.frame.minY + 0.5, "\(kind) is not under Connect", file: file, line: line) }
        }
        let cards = kinds.map { card(app, $0).frame }
        for (above, below) in zip(cards, cards.dropFirst()) { XCTAssertLessThanOrEqual(above.maxY, below.minY + 0.5, "the cards do not overlap", file: file, line: line) }
    }

    func testTheCardsSayWhatTheyRead() {
        let app = health()
        QA.pause(2)
        for (kind, words) in [("sleepAnalysis", "Sleep"), ("heartRate", "Heart rate"), ("hrv", "HRV")] {
            XCTAssertTrue(card(app, kind).label.hasPrefix(words), "\(kind): \(card(app, kind).label)")
        }
        XCTAssertEqual(card(app, "sleepAnalysis").label, "Sleep, how long and consistently you sleep")
        XCTAssertTrue(app.descendants(matching: .any)["health.privacy"].label.hasPrefix("Read-only."))
    }

    func testNothingIsClippedAtTheDefaultSize() {
        let app = health()
        QA.pause(2)
        assertFits(app, scrolls: false)
        QA.shot("health-default")
    }

    func testNothingIsClippedAtTheLargestText() {
        let app = health(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        QA.pause(2)
        assertFits(app, scrolls: true)
        QA.shot("health-xxxl")
    }

    func testContinueWithoutHealthDataGoesOn() {
        let app = health()
        QA.pause(1.5)
        app.buttons["health.skip"].tap()
        XCTAssertTrue(app.buttons["notifications.allow"].waitForExistence(timeout: 8), "the Notifications step follows")
    }

    func testConnectGoesOnWhateverTheSheetSaid() {
        let app = health()
        QA.pause(1.5)
        app.buttons["health.connect"].tap()
        XCTAssertTrue(app.buttons["notifications.allow"].waitForExistence(timeout: 10), "the Notifications step follows")
    }

    func testBackGoesToTheSampleNight() {
        let app = health()
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["sample.continue"].waitForExistence(timeout: 8))
    }
}
