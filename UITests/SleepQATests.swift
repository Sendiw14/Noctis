import XCTest

/// The Sleep tab (APP_RULES.md R11), fast pass: iPhone 17 Pro, light and
/// dark. Each test opens the tab on a mock scenario and captures the
/// screen, then pages down through it.
@MainActor
final class SleepQATests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchSleep(_ scenario: String = "full", extra: [String] = []) -> XCUIApplication {
        QA.launch(extra: ["-useMockHealth", "-mockScenario", scenario, "-noctisSkipOnboarding", "-noctisInitialRoute", "sleep"] + extra)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func settled(_ app: XCUIApplication, waitFor identifier: String) {
        XCTAssertTrue(element(app, identifier).waitForExistence(timeout: 12), identifier)
        QA.pause(3.2)
    }

    func testDay() {
        let app = launchSleep()
        settled(app, waitFor: "sleep.hero")
        QA.capturePages(app, "sleep-day", maxPages: 7)
    }

    func testDayOnTheMessyNight() {
        let app = launchSleep("messyNight")
        settled(app, waitFor: "sleep.hero")
        QA.capturePages(app, "sleep-messy", maxPages: 3)
    }

    func testSleepOnly() {
        let app = launchSleep("sleepOnly")
        settled(app, waitFor: "sleep.hero")
        QA.capturePages(app, "sleep-sleeponly", maxPages: 4)
    }

    func testLearning() {
        let app = launchSleep("learning")
        settled(app, waitFor: "sleep.learning")
        QA.capturePages(app, "sleep-learning", maxPages: 4)
    }

    func testEmpty() {
        let app = launchSleep("empty")
        settled(app, waitFor: "sleep.state")
        QA.shot("sleep-empty")
    }

    func testGap() {
        let app = launchSleep("gap")
        settled(app, waitFor: "sleep.noNight")
        QA.capturePages(app, "sleep-gap", maxPages: 2)
    }

    // MARK: - Interaction

    /// Choosing another night in the strip changes the hero (and the
    /// selected capsule) without leaving the tab.
    func testChoosingAnotherNight() {
        let app = launchSleep()
        settled(app, waitFor: "sleep.hero")
        let hero = element(app, "sleep.hero")
        let before = hero.label
        XCTAssertTrue(before.hasPrefix("Last Night, slept"), before)
        let nights = app.buttons.matching(NSPredicate(format: "label MATCHES '.*, slept .*'"))
        XCTAssertGreaterThanOrEqual(nights.count, 10)
        // A night four before the last.
        let target = nights.element(boundBy: nights.count - 5)
        XCTAssertTrue(target.isSelected == false)
        target.tap()
        QA.pause(1)
        XCTAssertTrue(target.isSelected)
        XCTAssertNotEqual(hero.label, before)
        XCTAssertFalse(hero.label.hasPrefix("Last Night"), hero.label)
        QA.shot("sleep-other-night")
    }

    /// Tapping a stage total highlights that stage across the night; the
    /// landscape's value says which.
    func testTappingAStageTotalHighlightsItsStage() {
        let app = launchSleep()
        settled(app, waitFor: "sleep.hero")
        let chart = QA.element(app, labelBeginsWith: "Sleep stages chart")
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        let deep = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Deep '")).firstMatch
        XCTAssertTrue(deep.waitForExistence(timeout: 5))
        while !deep.isHittable { app.swipeUp() ; QA.pause(0.3) }
        deep.tap()
        QA.pause(0.8)
        XCTAssertTrue(((chart.value as? String) ?? "").hasPrefix("Deep · "), (chart.value as? String) ?? "")
        QA.shot("sleep-stage-highlight")
        deep.tap()
        QA.pause(0.6)
        XCTAssertEqual((chart.value as? String) ?? "", "")
    }
}
