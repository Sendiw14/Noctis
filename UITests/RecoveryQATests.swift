import XCTest

/// The Recovery tab (APP_RULES.md R11), fast pass: iPhone 17 Pro, light and
/// dark. Each test opens the tab on a mock scenario and captures the screen,
/// then pages down through it.
@MainActor
final class RecoveryQATests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchRecovery(_ scenario: String = "full", extra: [String] = []) -> XCUIApplication {
        QA.launch(extra: ["-useMockHealth", "-mockScenario", scenario, "-noctisSkipOnboarding", "-noctisInitialRoute", "recovery"] + extra)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func settled(_ app: XCUIApplication, waitFor identifier: String) {
        XCTAssertTrue(element(app, identifier).waitForExistence(timeout: 12), identifier)
        QA.pause(3.2)
    }

    /// Scrolls until `target` is on screen (a few swipes at most).
    private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<8 where !target.isHittable {
            scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
                .press(forDuration: 0.05, thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.35)), withVelocity: .slow, thenHoldForDuration: 0.3)
            QA.pause(0.4)
        }
        QA.pause(0.6)
    }

    func testToday() {
        let app = launchRecovery()
        settled(app, waitFor: "recovery.hero")
        XCTAssertTrue(element(app, "recovery.build").exists)
        QA.capturePages(app, "recovery-today", maxPages: 7)
        XCTAssertTrue(element(app, "recovery.confidence").exists)
    }

    func testSleepOnly() {
        let app = launchRecovery("sleepOnly")
        settled(app, waitFor: "recovery.hero")
        QA.capturePages(app, "recovery-sleeponly", maxPages: 6)
        let step = element(app, "recovery.nextStep")
        XCTAssertTrue(step.exists)
    }

    func testLearning() {
        let app = launchRecovery("learning")
        settled(app, waitFor: "recovery.learning")
        QA.shot("recovery-learning")
    }

    func testEmpty() {
        let app = launchRecovery("empty")
        settled(app, waitFor: "recovery.state")
        QA.shot("recovery-empty")
    }

    func testGap() {
        let app = launchRecovery("gap")
        settled(app, waitFor: "recovery.noSleep")
        QA.shot("recovery-gap")
    }

    func testRecoveryDip() {
        let app = launchRecovery("recoveryDip")
        settled(app, waitFor: "recovery.hero")
        QA.capturePages(app, "recovery-dip", maxPages: 3)
    }

    /// A factor card opens that factor's page, and back returns to Today.
    func testAFactorCardOpensItsDetail() {
        let app = launchRecovery()
        settled(app, waitFor: "recovery.hero")
        let card = element(app, "recovery.factor.hrv")
        reveal(card, in: app)
        card.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        QA.pause(0.8)
        QA.shot("recovery-factor-opened")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(element(app, "recovery.hero").waitForExistence(timeout: 5))
    }

    /// The stacked bar's rows add up to the total beside it.
    func testTheBuildRowsAddUpToTheTotal() {
        let app = launchRecovery()
        settled(app, waitFor: "recovery.build")
        let label = element(app, "recovery.build").label
        // "How today's score was built: Sleep, 24 points, …; HRV, 15 points, …. Total 70."
        let points = label.matches(of: /(\d+) points/).compactMap { Int($0.1) }
        let total = label.firstMatch(of: /Total (\d+)\./).flatMap { Int($0.1) }
        XCTAssertEqual(points.count, 4, label)
        XCTAssertEqual(points.reduce(0, +), total, label)
    }
}
