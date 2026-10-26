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
        let found = element(app, identifier).waitForExistence(timeout: 12)
        if !found {
            QA.write(app.debugDescription, to: "missing-\(identifier).txt")
            QA.shot("missing-\(identifier)")
        }
        XCTAssertTrue(found, identifier)
        QA.pause(3.2)
    }

    /// Scrolls until `target` is on screen (a few swipes at most).
    private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<8 where !target.isHittable {
            scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
                .press(
                    forDuration: 0.05, thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.35)), withVelocity: .slow,
                    thenHoldForDuration: 0.3)
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

    /// No Health access: the dormant ring, "Your first night starts here." and
    /// the one action, with no score anywhere.
    func testNoPermission() {
        let app = launchRecovery("full", extra: ["-mockUnauthorized"])
        settled(app, waitFor: "recovery.state")
        XCTAssertTrue(app.buttons["Connect Apple Health"].exists)
        XCTAssertFalse(element(app, "recovery.hero").exists)
        QA.shot("recovery-nopermission")
    }

    /// A failed read is its own state, with "Try again", not "no data".
    func testError() {
        let app = launchRecovery("full", extra: ["-noctisHealthQueryFails"])
        settled(app, waitFor: "recovery.state")
        XCTAssertTrue(app.buttons["Try again"].exists)
        XCTAssertFalse(element(app, "recovery.hero").exists)
        QA.shot("recovery-error")
    }

    /// Nothing newer than 30 hours: Home's words, not a claim of no sleep.
    func testStale() {
        let app = launchRecovery("stale")
        settled(app, waitFor: "recovery.noSleep")
        XCTAssertTrue(QA.text(app, containing: "hasn't updated").exists)
        QA.shot("recovery-stale")
    }

    /// The first snapshot is loading: blocks shaped like the segment, and the
    /// segment control is already there.
    func testSkeleton() {
        let app = launchRecovery("full", extra: ["-mockLatency", "8"])
        XCTAssertTrue(element(app, "recovery.skeleton").waitForExistence(timeout: 8))
        QA.shot("recovery-skeleton")
        XCTAssertTrue(element(app, "recovery.hero").waitForExistence(timeout: 20))
    }

    /// A second press of the Recovery tab scrolls it back to the top.
    func testPressingTheRecoveryTabAgainScrollsToTheTop() {
        let app = launchRecovery()
        settled(app, waitFor: "recovery.hero")
        let hero = element(app, "recovery.hero")
        let topY = hero.frame.minY
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<2 {
            scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
                .press(
                    forDuration: 0.05, thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.2)), withVelocity: .slow,
                    thenHoldForDuration: 0.3)
            QA.pause(0.4)
        }
        XCTAssertNotEqual(hero.frame.minY, topY, accuracy: 20, "scrolled away")
        // Scrolling minimizes the tab bar: its button opens the bar, then the
        // Recovery tab's is a press on the tab that's already showing.
        let tab = app.tabBars.buttons["Recovery"]
        XCTAssertTrue(tab.waitForExistence(timeout: 3))
        tab.tap()
        QA.pause(0.8)
        if abs(hero.frame.minY - topY) > 2 {
            tab.tap()
            QA.pause(1.2)
        }
        XCTAssertEqual(hero.frame.minY, topY, accuracy: 2)
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

    // MARK: - Factor detail

    private func openFactor(_ identifier: String, in app: XCUIApplication) {
        let card = element(app, identifier)
        reveal(card, in: app)
        card.tap()
        XCTAssertTrue(element(app, "recovery.factorScreen").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "recovery.factorChart").waitForExistence(timeout: 5))
        QA.pause(1.2)
    }

    func testTheFactorPageAndItsRanges() {
        let app = launchRecovery()
        settled(app, waitFor: "recovery.hero")
        openFactor("recovery.factor.hrv", in: app)
        QA.capturePages(app, "recovery-factor-14", maxPages: 4)
        let ranges = app.segmentedControls["recovery.factorRange"]
        // Scrolled away with the page; scroll back to the top.
        for _ in 0..<4 where !ranges.isHittable { app.swipeDown() }
        QA.pause(0.6)
        for name in ["30 nights", "90 nights", "14 nights"] {
            ranges.buttons[name].tap()
            QA.pause(1.4)
            XCTAssertTrue(ranges.buttons[name].isSelected, name)
            QA.shot("recovery-factor-\(name.prefix(2))")
        }
    }

    /// A tap on the chart picks a night and the pill says what it was; a tap
    /// on the same night clears it.
    func testTappingTheFactorChartSelectsANight() {
        let app = launchRecovery()
        settled(app, waitFor: "recovery.hero")
        openFactor("recovery.factor.restingHeartRate", in: app)
        let chart = element(app, "recovery.factorChart")
        let spot = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.45))
        spot.tap()
        QA.pause(0.6)
        let value = (chart.value as? String) ?? ""
        XCTAssertTrue(value.contains("resting heart rate"), value)
        QA.shot("recovery-factor-selected")
        spot.tap()
        QA.pause(0.6)
        XCTAssertEqual((chart.value as? String) ?? "", "")
    }

    func testEveryFactorHasAPage() {
        for identifier in ["recovery.factor.sleepDuration", "recovery.factor.sleepConsistency"] {
            let app = launchRecovery()
            settled(app, waitFor: "recovery.hero")
            openFactor(identifier, in: app)
            QA.shot("recovery-\(identifier.split(separator: ".").last ?? "factor")")
            app.terminate()
        }
    }

    // MARK: - History

    private func launchRange(_ token: String, scenario: String = "full") -> XCUIApplication {
        QA.launch(extra: ["-useMockHealth", "-mockScenario", scenario, "-noctisSkipOnboarding", "-noctisInitialRoute", "recovery:\(token)"])
    }

    func testHistoryRanges() {
        for (token, name) in [("7d", "7d"), ("30d", "30d"), ("90d", "90d")] {
            let app = launchRange(token)
            settled(app, waitFor: "recovery.historyChart")
            XCTAssertTrue(element(app, "recovery.stats").exists, token)
            XCTAssertTrue(element(app, "recovery.usualLine").exists, token)
            QA.capturePages(app, "recovery-\(name)", maxPages: 4)
            app.terminate()
        }
    }

    func testTheDipShowsInTheWeek() {
        let app = launchRange("30d", scenario: "recoveryDip")
        settled(app, waitFor: "recovery.historyChart")
        QA.capturePages(app, "recovery-dip-30d", maxPages: 2)
    }

    /// Switching segments keeps the tab, and comes back to Today.
    func testSwitchingSegments() {
        let app = launchRecovery()
        settled(app, waitFor: "recovery.hero")
        for name in ["7D", "30D", "90D", "Today"] {
            app.buttons["recovery.range.\(name)"].tap()
            XCTAssertTrue(element(app, name == "Today" ? "recovery.hero" : "recovery.historyChart").waitForExistence(timeout: 5), name)
            QA.pause(0.8)
        }
        XCTAssertFalse(element(app, "recovery.historyChart").exists)
    }

    /// A tap on the chart picks a day and the pill says what it was.
    func testTappingTheHistoryChartSelectsADay() {
        let app = launchRange("30d")
        settled(app, waitFor: "recovery.historyChart")
        let chart = element(app, "recovery.historyChart")
        let spot = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
        spot.tap()
        QA.pause(0.6)
        let value = (chart.value as? String) ?? ""
        XCTAssertTrue(value.contains("recovery"), value)
        QA.shot("recovery-history-selected")
        spot.tap()
        QA.pause(0.6)
        XCTAssertEqual((chart.value as? String) ?? "", "")
    }

    /// A factor row opens that factor's page on the same range.
    func testAHistoryFactorRowOpensItsPageOnTheSameRange() {
        let app = launchRange("30d")
        settled(app, waitFor: "recovery.historyChart")
        let row = element(app, "recovery.historyFactor.hrv")
        reveal(row, in: app)
        row.tap()
        XCTAssertTrue(element(app, "recovery.factorScreen").waitForExistence(timeout: 5))
        QA.pause(1)
        XCTAssertTrue(app.segmentedControls["recovery.factorRange"].buttons["30 nights"].isSelected)
        QA.shot("recovery-history-factor-30")
    }

    /// The draw-in itself is timing: frames of it come from `simctl io screenshot`
    /// right after launch (an XCUITest screenshot lands after it has finished).
    /// This checks the chart is fully there once it has.
    func testTheHistoryChartIsDrawnOnceTheFirstVisitSettles() {
        let app = QA.launch(extra: ["-useMockHealth", "-mockScenario", "full", "-noctisSkipOnboarding", "-noctisInitialRoute", "recovery:30d"], reset: true)
        XCTAssertTrue(element(app, "recovery.historyChart").waitForExistence(timeout: 12))
        QA.pause(2.5)
        QA.shot("recovery-30d-settled")
        XCTAssertTrue(element(app, "recovery.stats").exists)
    }
}
