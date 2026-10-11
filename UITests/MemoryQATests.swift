import XCTest

/// QA part 2 (QA_LEDGER.md 2.8): what each tab and each pushed screen leaves behind in memory after being opened and closed twenty times.
/// One test per screen, so a screen that keeps something shows by name. Each test warms the screen up once, reads the app's own footprint
/// (`phys_footprint`, from the DEBUG probe on Home, the number `XCTMemoryMetric` calls physical memory), opens and closes the screen twenty
/// times, and reads it again; the growth may not reach 5 MB. `testRecoveryZoomFromHome` also runs under `XCTMemoryMetric` so the result bundle
/// holds the metric's own figures (XCTest runs a measured block once more as its warm-up, which doubles a test: only that one test pays it).
///
/// The simulator's numbers are a smoke test of what the screens leave behind, not the device budget.
@MainActor
final class MemoryQATests: XCTestCase {
    private static let laps = 20
    private static let budgetMegabytes = 5.0

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Helpers

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func hero(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.hero'")).firstMatch
    }

    /// The footprint and the memory the allocator holds as reusable (the label's `reusable=`), in megabytes. The footprint alone swings with the
    /// allocator reusing pages (QA_LEDGER.md), so a leak is judged on the two together.
    private func probeMegabytes(_ app: XCUIApplication) -> (footprint: Double, reusable: Double) {
        let probe = element(app, "debug.probe")
        XCTAssertTrue(probe.waitForExistence(timeout: 10), "Launch with -noctisDebugProbe, on Home.")
        let reusable = probe.label.split(separator: ";").first { $0.hasPrefix("reusable=") }.flatMap { Double($0.dropFirst("reusable=".count)) } ?? 0
        return (Double(probe.value as? String ?? "") ?? 0, reusable)
    }

    /// Taps `target` when it exists within `timeout`; the lap fails with `what` when it does not.
    private func tap(_ target: XCUIElement, _ what: String, timeout: TimeInterval = 10) {
        XCTAssertTrue(target.waitForExistence(timeout: timeout), what)
        target.tap()
    }

    private func back(_ app: XCUIApplication, _ what: String) {
        let button = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), what)
        button.tap()
    }

    /// A tab bar that minimized while a screen was scrolled comes back when the page is scrolled to its top.
    private func tapTab(_ app: XCUIApplication, _ name: String) {
        let button = app.tabBars.buttons[name]
        var attempts = 0
        while !(button.exists && button.isHittable), attempts < 8 {
            app.swipeDown()
            attempts += 1
        }
        tap(button, "\(name) tab")
    }

    /// Back on Home with its hero in view (Home keeps the scroll position it was left at).
    private func home(_ app: XCUIApplication) {
        tapTab(app, "Home")
        var attempts = 0
        while !hero(app).exists, attempts < 6 {
            app.swipeDown()
            attempts += 1
        }
        XCTAssertTrue(hero(app).waitForExistence(timeout: 10), "Home's hero")
    }

    /// One warm-up cycle, the baseline, twenty cycles, the footprint again. The numbers go to `memory-<name>.txt`.
    private func openAndCloseTwenty(_ name: String, extra: [String] = [], measured: Bool = false, cycle: (XCUIApplication) -> Void) {
        let app = QA.launch(extra: [
            "-useMockHealth", "-mockScenario", "full", "-noctisSkipOnboarding", "-homeMode", "day", "-noctisDebugProbe", "-forceTier", "premium",
            "-seedReviews",
        ] + extra)
        XCTAssertTrue(hero(app).waitForExistence(timeout: 20), "Home")
        cycle(app)
        let baseline = probeMegabytes(app)

        var samples: [(footprint: Double, reusable: Double)] = []
        var stamps: [Int] = []
        let started = Date()
        func twentyLaps() {
            for _ in 1...Self.laps {
                cycle(app)
                samples.append(probeMegabytes(app))
                stamps.append(Int(Date().timeIntervalSince(started)))
            }
        }
        if measured {
            let options = XCTMeasureOptions()
            options.iterationCount = 1
            measure(metrics: [XCTMemoryMetric(application: app)], options: options) {
                // The block runs twice (a warm-up and the measurement): the growth is judged on the first twenty laps.
                twentyLaps()
            }
        } else {
            twentyLaps()
        }
        let after = samples.count >= Self.laps ? samples[Self.laps - 1] : (samples.last ?? probeMegabytes(app))
        // The footprint and the allocator's reusable pages together: what the process holds, however the allocator has divided it.
        let growth = (after.footprint + after.reusable) - (baseline.footprint + baseline.reusable)
        let footprintGrowth = after.footprint - baseline.footprint
        let line = """
            \(name): footprint+reusable at the baseline \(String(format: "%.1f", baseline.footprint + baseline.reusable)) MB \
            (\(String(format: "%.1f", baseline.footprint)) + \(String(format: "%.1f", baseline.reusable))); after each lap \
            \(samples.prefix(Self.laps).map { String(format: "%.1f+%.1f", $0.footprint, $0.reusable) }.joined(separator: " ")) MB; \
            growth \(String(format: "%.1f", growth)) MB (the footprint alone \(String(format: "%.1f", footprintGrowth)) MB); \
            seconds since the baseline \(stamps.prefix(Self.laps).map(String.init).joined(separator: " "))
            """
        QA.write(line, to: "memory-\(name).txt")
        XCTAssertLessThan(growth, Self.budgetMegabytes, line)
    }

    // MARK: The tabs

    func testSleepWithItsThreeRanges() {
        openAndCloseTwenty("sleep") { app in
            tapTab(app, "Sleep")
            let range = element(app, "sleep.range")
            XCTAssertTrue(range.waitForExistence(timeout: 10), "Sleep's range control")
            let segments = range.buttons
            for index in 0..<min(segments.count, 3) where segments.element(boundBy: index).isHittable { segments.element(boundBy: index).tap() }
            home(app)
        }
    }

    func testRecoveryTab() {
        openAndCloseTwenty("recovery-tab") { app in
            tapTab(app, "Recovery")
            XCTAssertTrue(element(app, "recovery.hero").waitForExistence(timeout: 10), "Recovery's hero")
            home(app)
        }
    }

    func testInsightsTabAndAnInsightsPage() {
        openAndCloseTwenty("insights") { app in
            tapTab(app, "Insights")
            let featured = element(app, "insights.featured")
            XCTAssertTrue(featured.waitForExistence(timeout: 10), "The featured insight")
            featured.tap()
            XCTAssertTrue(element(app, "insights.detail").waitForExistence(timeout: 10), "An insight's page")
            back(app, "Back from an insight")
            home(app)
        }
    }

    func testReviewsListAndAStory() {
        openAndCloseTwenty("reviews") { app in
            tapTab(app, "Insights")
            tap(element(app, "insights.reviews"), "The reviews' entry")
            XCTAssertTrue(element(app, "reviews.list").waitForExistence(timeout: 10), "The reviews' list")
            let first = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'reviews.row.'")).firstMatch
            tap(first, "A review's row")
            // The story's container carries `review.story.<kind>` and that identifier covers its buttons' own (QA_LEDGER.md): by label.
            tap(app.buttons["Close"], "A review's story")
            back(app, "Back from the reviews' list")
            home(app)
        }
    }

    func testCoachQuestionAndConversation() {
        openAndCloseTwenty("coach") { app in
            tapTab(app, "Coach")
            let dismissFirstRun = element(app, "coach.firstRun.dismiss")
            if dismissFirstRun.waitForExistence(timeout: 2) { dismissFirstRun.tap() }
            tap(element(app, "coach.question.recovery.lower"), "A Coach question", timeout: 10)
            XCTAssertTrue(element(app, "coach.conversation").waitForExistence(timeout: 20), "Coach's conversation")
            back(app, "Back from the conversation")
            home(app)
        }
    }

    // MARK: Pushed from Home

    func testRecoveryZoomFromHome() {
        openAndCloseTwenty("recovery-zoom", measured: true) { app in
            tap(hero(app), "Home's hero")
            XCTAssertTrue(element(app, "recovery.hero").waitForExistence(timeout: 10), "Recovery opened from Home")
            back(app, "Back from Recovery")
            XCTAssertTrue(hero(app).waitForExistence(timeout: 10), "Home again")
        }
    }

    func testTonight() {
        openAndCloseTwenty("tonight") { app in
            openTonight(app)
            back(app, "Back from Tonight")
            home(app)
        }
    }

    func testSleepSounds() {
        openAndCloseTwenty("sounds") { app in
            openTonight(app)
            tap(element(app, "tonight.sounds"), "Tonight's Sounds tile")
            XCTAssertTrue(element(app, "sounds.screen").waitForExistence(timeout: 10), "Sleep sounds")
            back(app, "Back from Sounds")
            back(app, "Back from Tonight")
            home(app)
        }
    }

    func testWindDown() {
        openAndCloseTwenty("wind-down") { app in
            openTonight(app)
            tap(element(app, "tonight.windDown"), "Tonight's wind-down button")
            XCTAssertTrue(element(app, "windDown.screen").waitForExistence(timeout: 10), "Wind-down")
            // By label: the screen's container identifier covers its buttons' own on this OS (QA_LEDGER.md).
            tap(app.buttons["Not now"], "Wind-down's way out")
            // "Not now" lands on Tonight when it was opened over Tonight, and on Home when Tonight was not in the stack.
            if !hero(app).exists, element(app, "tonight.screen").waitForExistence(timeout: 3) { back(app, "Back from Tonight") }
            home(app)
        }
    }

    /// Home's Tonight block sits below the fold.
    private func openTonight(_ app: XCUIApplication) {
        let tonight = element(app, "home.tonightBlock")
        var attempts = 0
        while !(tonight.exists && tonight.isHittable), attempts < 4 {
            app.swipeUp()
            attempts += 1
        }
        tap(tonight, "Home's Tonight block")
        XCTAssertTrue(element(app, "tonight.screen").waitForExistence(timeout: 10), "Tonight")
    }
}
