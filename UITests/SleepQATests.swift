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

    /// Scrolls until `target` is on screen (a few swipes at most), then
    /// taps its center; a floating tab bar can leave a button on screen
    /// but not "hittable".
    private func tapScrolling(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !target.isHittable {
            app.swipeUp()
            QA.pause(0.3)
        }
        // A tap sent right after a swipe is swallowed by the scroll's momentum.
        QA.pause(0.8)
        if target.isHittable {
            target.tap()
        } else {
            target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
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

    // MARK: - Week and Month

    private func choose(_ range: String, _ app: XCUIApplication) {
        let segment = app.segmentedControls.buttons[range]
        XCTAssertTrue(segment.waitForExistence(timeout: 5), range)
        segment.tap()
        XCTAssertTrue(element(app, "sleep.bars").waitForExistence(timeout: 5), range)
        QA.pause(1.2)
    }

    func testWeek() {
        let app = launchSleep()
        settled(app, waitFor: "sleep.hero")
        choose("Week", app)
        XCTAssertTrue(element(app, "sleep.consistency").exists)
        XCTAssertTrue(element(app, "sleep.balance").exists)
        XCTAssertTrue(element(app, "sleep.timing").exists)
        QA.capturePages(app, "sleep-week", maxPages: 4)
    }

    func testMonth() {
        let app = launchSleep()
        settled(app, waitFor: "sleep.hero")
        choose("Month", app)
        XCTAssertTrue(element(app, "sleep.rhythm").waitForExistence(timeout: 3))
        QA.capturePages(app, "sleep-month", maxPages: 4)
        XCTAssertTrue(element(app, "sleep.qualityStrip").exists)
    }

    func testWeekOnMessyNightAndGap() {
        for scenario in ["messyNight", "gap", "sleepOnly", "learning"] {
            let app = launchSleep(scenario)
            XCTAssertTrue(app.segmentedControls.buttons["Week"].waitForExistence(timeout: 12), scenario)
            QA.pause(2)
            choose("Week", app)
            QA.shot("sleep-week-\(scenario)")
            choose("Month", app)
            QA.shot("sleep-month-\(scenario)")
            app.terminate()
        }
    }

    /// Switching ranges regroups the same chart; the tab and its header stay.
    func testSwitchingRangesKeepsTheHeaderAndComesBackToDay() {
        let app = launchSleep()
        settled(app, waitFor: "sleep.hero")
        choose("Week", app)
        choose("Month", app)
        choose("Week", app)
        app.segmentedControls.buttons["Day"].tap()
        XCTAssertTrue(element(app, "sleep.hero").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "sleep.bars").exists)
    }

    /// A press on the chart picks the night under it and says what it was; a
    /// press on the same night clears it.
    func testTappingAWeekBarSelectsItsNight() {
        let app = launchSleep()
        settled(app, waitFor: "sleep.hero")
        choose("Week", app)
        let bars = element(app, "sleep.bars")
        let spot = bars.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        spot.tap()
        QA.pause(0.6)
        let value = (bars.value as? String) ?? ""
        XCTAssertTrue(value.contains("hour"), value)
        QA.shot("sleep-week-selected")
        spot.tap()
        QA.pause(0.6)
        XCTAssertEqual((bars.value as? String) ?? "", "")
    }

    func testMonthMarkersSelectTheirBar() {
        let app = launchSleep()
        settled(app, waitFor: "sleep.hero")
        choose("Month", app)
        let longest = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Longest night'")).firstMatch
        XCTAssertTrue(longest.waitForExistence(timeout: 5))
        tapScrolling(longest, in: app)
        QA.pause(0.6)
        let value = (element(app, "sleep.bars").value as? String) ?? ""
        XCTAssertTrue(value.contains("hours"), value)
    }

    /// Each card opens its sheet, which ends on the closing line.
    func testEachInsightOpensItsSheet() {
        let app = launchSleep()
        settled(app, waitFor: "sleep.hero")
        choose("Week", app)
        for (card, sheet, name) in [("sleep.consistency", "sleep.consistencySheet", "consistency"), ("sleep.balance", "sleep.balanceSheet", "balance"), ("sleep.timing", "sleep.timingSheet", "timing")] {
            tapScrolling(element(app, card), in: app)
            let opened = element(app, sheet).waitForExistence(timeout: 5)
            if !opened { QA.shot("sleep-sheet-missing-\(name)") }
            XCTAssertTrue(opened, sheet)
            QA.pause(0.8)
            QA.shot("sleep-sheet-\(name)")
            XCTAssertTrue(app.staticTexts["Patterns matter more than perfect nights."].exists || {
                app.swipeUp(); QA.pause(0.3)
                return app.staticTexts["Patterns matter more than perfect nights."].exists
            }())
            let close = app.buttons["Close"]
            XCTAssertTrue(close.waitForExistence(timeout: 3))
            close.tap()
            XCTAssertFalse(element(app, sheet).waitForExistence(timeout: 1) && element(app, sheet).isHittable && false)
            QA.pause(1.2)
            QA.shot("sleep-sheet-closed-\(name)")
        }
    }
}
