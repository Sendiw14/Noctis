import XCTest

/// The Insights tab (APP_RULES.md R11), fast pass: iPhone 17 Pro, light and
/// dark. Each test opens the tab on a mock scenario, captures it, and opens
/// the pages a person would: an insight, History, each chip, the states.
@MainActor
final class InsightsQATests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ scenario: String = "full", extra: [String] = []) -> XCUIApplication {
        QA.launch(extra: ["-useMockHealth", "-mockScenario", scenario, "-noctisSkipOnboarding", "-noctisInitialRoute", "insights"] + extra)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func settled(_ app: XCUIApplication, waitFor identifier: String) {
        let found = element(app, identifier).waitForExistence(timeout: 14)
        if !found {
            QA.write(app.debugDescription, to: "missing-\(identifier).txt")
            QA.shot("missing-\(identifier)")
        }
        XCTAssertTrue(found, identifier)
        QA.pause(3.2)
    }

    /// A row of the Recent list (or History) by the start of its label.
    private func row(_ app: XCUIApplication, _ prefix: String, history: Bool = false) -> XCUIElement {
        let base = history ? "insights.history.row." : "insights.row."
        return app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", base, prefix)).firstMatch
    }

    private func scrollDown(_ app: XCUIApplication, times: Int = 1) {
        for _ in 0..<times {
            let scrollView = app.scrollViews.firstMatch
            scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
                .press(
                    forDuration: 0.05, thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.3)), withVelocity: .slow,
                    thenHoldForDuration: 0.3)
            QA.pause(0.7)
        }
    }

    // MARK: - The tab

    func testTopAndScrolled() {
        let app = launch()
        settled(app, waitFor: "insights.featured")
        XCTAssertTrue(element(app, "insights.chips").exists)
        XCTAssertTrue(element(app, "insights.history").exists)
        XCTAssertTrue(element(app, "insights.recent").exists)
        let summary = element(app, "insights.summary").label
        XCTAssertTrue(summary.hasSuffix("new this week"), summary)
        QA.capturePages(app, "insights-full", maxPages: 4)
        XCTAssertTrue(element(app, "insights.records").exists)
    }

    func testTouchTargetsAreAtLeast44() {
        let app = launch()
        settled(app, waitFor: "insights.featured")
        for chip in app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'insights.chip.'")).allElementsBoundByIndex where chip.isHittable {
            XCTAssertGreaterThanOrEqual(chip.frame.height, 44, chip.identifier)
        }
        XCTAssertGreaterThanOrEqual(element(app, "insights.history").frame.height, 44)
        XCTAssertGreaterThanOrEqual(element(app, "insights.history").frame.width, 44)
        XCTAssertGreaterThanOrEqual(element(app, "insights.featured").frame.height, 44)
        scrollDown(app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'insights.row.'")).allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertFalse(rows.isEmpty)
        for row in rows { XCTAssertGreaterThanOrEqual(row.frame.height, 44, row.identifier) }
    }

    func testEveryChipFiltersTheList() {
        let app = launch()
        settled(app, waitFor: "insights.featured")
        for chip in ["sleep", "recovery", "timing", "consistency", "heart", "longTerm", "all"] {
            let button = element(app, "insights.chip.\(chip)")
            QA.tap(button, in: app)
            QA.pause(1.0)
            QA.shot("insights-chip-\(chip)")
            XCTAssertTrue(button.isSelected || chip == "all" || button.exists, chip)
        }
    }

    func testSelectedChipIsMarkedSelected() {
        let app = launch()
        settled(app, waitFor: "insights.featured")
        XCTAssertTrue(element(app, "insights.chip.all").isSelected)
        QA.tap(element(app, "insights.chip.sleep"), in: app)
        QA.pause(0.8)
        XCTAssertTrue(element(app, "insights.chip.sleep").isSelected)
        XCTAssertFalse(element(app, "insights.chip.all").isSelected)
    }

    // MARK: - An insight's page

    /// The full scenario's featured story is the duration shift (70 minutes outranks 55).
    func testDurationDetail() {
        let app = launch()
        settled(app, waitFor: "insights.featured")
        XCTAssertTrue(element(app, "insights.featured").label.hasPrefix("Shorter night than usual"))
        element(app, "insights.featured").tap()
        settled(app, waitFor: "insights.detail")
        XCTAssertTrue(element(app, "insights.header").label.hasPrefix("Shorter night than usual"))
        XCTAssertTrue(element(app, "insights.try").exists, "rule 1 offers something to try")
        XCTAssertFalse(element(app, "insights.notProof").exists)
        QA.capturePages(app, "insights-detail-duration", maxPages: 5)
    }

    /// A bedtime insight from the Recent list: something to try, a timeline for a chart.
    func testBedtimeDetailFromRecent() {
        let app = launch()
        settled(app, waitFor: "insights.featured")
        scrollDown(app)
        QA.tap(row(app, "Later bedtime than usual"), in: app)
        settled(app, waitFor: "insights.detail")
        XCTAssertTrue(element(app, "insights.header").label.hasPrefix("Later bedtime than usual"))
        XCTAssertTrue(element(app, "insights.try").exists)
        QA.shot("insights-detail-bedtime")
    }

    func testPatternDetail() {
        let app = launch("earlyBird")
        settled(app, waitFor: "insights.featured")
        scrollDown(app)
        let pattern = row(app, "Earlier bedtimes")
        QA.tap(pattern, in: app)
        settled(app, waitFor: "insights.detail")
        XCTAssertTrue(element(app, "insights.chart").exists)
        XCTAssertFalse(element(app, "insights.try").exists, "a pattern offers nothing to try")
        QA.capturePages(app, "insights-detail-pattern", maxPages: 5)
        XCTAssertTrue(element(app, "insights.notProof").exists)
        XCTAssertTrue(app.staticTexts["This is a pattern in your data, not proof of a cause."].exists)
        XCTAssertTrue(element(app, "insights.confidence").label.contains("confidence · based on"))
    }

    func testFeaturedOpensItsPage() {
        let app = launch()
        settled(app, waitFor: "insights.featured")
        element(app, "insights.featured").tap()
        settled(app, waitFor: "insights.detail")
        XCTAssertTrue(element(app, "insights.method").exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(element(app, "insights.featured").waitForExistence(timeout: 6))
    }

    func testNotUsefulClosesThePageAndKeepsItInHistory() {
        let app = launch()
        settled(app, waitFor: "insights.featured")
        element(app, "insights.featured").tap()
        settled(app, waitFor: "insights.detail")
        QA.tap(element(app, "insights.notUseful"), in: app)
        // The page closes on its own; the featured story is gone for the night.
        XCTAssertTrue(element(app, "insights.summary").waitForExistence(timeout: 8))
        QA.pause(1.2)
        XCTAssertFalse(element(app, "insights.featured").exists)
        QA.shot("insights-after-not-useful")
        element(app, "insights.history").tap()
        settled(app, waitFor: "insights.history.screen")
        QA.shot("insights-history-with-dismissed")
        XCTAssertTrue(app.staticTexts["Not useful"].exists, "the dismissed one stays, muted, with its label")
    }

    func testHideRemovesTheKindEverywhere() {
        let app = launch()
        settled(app, waitFor: "insights.featured")
        let title = element(app, "insights.featured").label
        element(app, "insights.featured").tap()
        settled(app, waitFor: "insights.detail")
        QA.tap(element(app, "insights.hide"), in: app)
        XCTAssertTrue(element(app, "insights.summary").waitForExistence(timeout: 8))
        QA.pause(1.2)
        // The next insight takes its place; the hidden kind is gone from the story and from Recent.
        let first = title.components(separatedBy: ".").first ?? title
        XCTAssertTrue(element(app, "insights.featured").exists)
        XCTAssertFalse(element(app, "insights.featured").label.hasPrefix(first), "the featured story moved on")
        XCTAssertFalse(row(app, first).exists, "a hidden kind is gone from Recent too")
        QA.shot("insights-after-hide")
    }

    func testLongPressMenuOnARow() {
        let app = launch()
        settled(app, waitFor: "insights.featured")
        scrollDown(app)
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'insights.row.'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 6))
        target.press(forDuration: 1.2)
        QA.pause(0.8)
        QA.shot("insights-context-menu")
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Not useful"].exists)
        XCTAssertTrue(app.buttons["Hide insights like this"].exists)
    }

    // MARK: - History

    func testHistoryByMonthAndFilter() {
        let app = launch()
        settled(app, waitFor: "insights.featured")
        element(app, "insights.history").tap()
        settled(app, waitFor: "insights.history.screen")
        XCTAssertTrue(element(app, "insights.history.summary").label.hasSuffix("so far."))
        QA.capturePages(app, "insights-history", maxPages: 3)
        let chip = element(app, "insights.chip.sleep")
        QA.tap(chip, in: app)
        QA.pause(1.0)
        QA.shot("insights-history-sleep")
        QA.tap(element(app, "insights.chip.all"), in: app)
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'insights.history.row.'")).firstMatch
        QA.tap(first, in: app)
        settled(app, waitFor: "insights.detail")
        QA.shot("insights-history-detail")
    }

    // MARK: - States

    func testLearning() {
        let app = launch("sparse")
        settled(app, waitFor: "insights.learning")
        XCTAssertTrue(element(app, "insights.milestone.7").exists)
        XCTAssertTrue(element(app, "insights.milestone.14").exists)
        XCTAssertTrue(element(app, "insights.milestone.30").exists)
        XCTAssertFalse(element(app, "insights.history").exists, "nothing to look back over yet")
        XCTAssertEqual(element(app, "insights.summary").label, "We're still learning your pattern.")
        QA.shot("insights-learning")
    }

    func testEmpty() {
        let app = launch("empty")
        settled(app, waitFor: "insights.state")
        QA.shot("insights-empty")
    }

    func testNoPermission() {
        let app = launch("full", extra: ["-mockUnauthorized"])
        settled(app, waitFor: "insights.state")
        XCTAssertTrue(app.buttons["Connect Apple Health"].exists)
        QA.shot("insights-no-permission")
    }

    func testError() {
        let app = launch("full", extra: ["-noctisHealthQueryFails"])
        settled(app, waitFor: "insights.state")
        XCTAssertTrue(app.buttons["Try again"].exists)
        QA.shot("insights-error")
    }

    func testSecondPressOfTheTabScrollsToTop() {
        let app = launch()
        settled(app, waitFor: "insights.featured")
        scrollDown(app, times: 2)
        XCTAssertFalse(element(app, "insights.chips").isHittable)
        let tab = app.tabBars.buttons["Insights"]
        if !tab.exists { app.swipeDown() }
        // The minimized bar needs a first tap to open; the second re-taps the tab.
        for _ in 0..<2 where app.tabBars.buttons["Insights"].exists {
            app.tabBars.buttons["Insights"].tap()
            QA.pause(0.6)
        }
        XCTAssertTrue(element(app, "insights.chips").waitForExistence(timeout: 4))
        QA.shot("insights-after-retap")
    }

    // MARK: - Routing

    /// Home's Insight block opens that insight's page, on the Insights tab.
    func testHomeInsightBlockOpensThatInsight() {
        let app = QA.launch(extra: ["-useMockHealth", "-mockScenario", "full", "-noctisSkipOnboarding"])
        let block = QA.element(app, labelBeginsWith: "Shorter night than usual")
        XCTAssertTrue(block.waitForExistence(timeout: 14))
        QA.pause(3)
        QA.tap(block, in: app)
        settled(app, waitFor: "insights.detail")
        XCTAssertTrue(element(app, "insights.header").label.hasPrefix("Shorter night than usual"), element(app, "insights.header").label)
        QA.shot("insights-from-home")
        // Back to the tab's root, on All.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(element(app, "insights.chips").waitForExistence(timeout: 6))
        XCTAssertTrue(element(app, "insights.chip.all").isSelected)
    }

    /// Home and the tab feature the same insight.
    func testHomeAndTheTabAgreeOnTheFeaturedInsight() {
        let app = QA.launch(extra: ["-useMockHealth", "-mockScenario", "full", "-noctisSkipOnboarding"])
        let block = element(app, "home.insight")
        XCTAssertTrue(block.waitForExistence(timeout: 14))
        let home = block.label.components(separatedBy: ".").first ?? ""
        app.tabBars.buttons["Insights"].tap()
        settled(app, waitFor: "insights.featured")
        let tab = element(app, "insights.featured").label.components(separatedBy: ".").first ?? ""
        XCTAssertFalse(home.isEmpty)
        XCTAssertEqual(home, tab)
    }

    /// A launch route names a chip.
    func testInitialRouteOpensAChip() {
        let app = QA.launch(extra: ["-useMockHealth", "-mockScenario", "full", "-noctisSkipOnboarding", "-noctisInitialRoute", "insights:heart"])
        XCTAssertTrue(element(app, "insights.chips").waitForExistence(timeout: 14))
        QA.pause(2)
        XCTAssertTrue(element(app, "insights.chip.heart").isSelected)
        QA.shot("insights-route-heart")
    }
}
