import XCTest

/// Home v3 (APP_RULES.md R11): full-size captures of each new piece. Every
/// capture writes the frame of what it shows (`<name>-frame.txt`, in
/// points) so it can be cropped at full resolution.
@MainActor
final class HomeV3QATests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchHome(_ scenario: String = "full", mode: String = "day") -> XCUIApplication {
        QA.launch(extra: ["-useMockHealth", "-mockScenario", scenario, "-noctisSkipOnboarding", "-homeMode", mode])
    }

    private func element(_ app: XCUIApplication, _ prefix: String) -> XCUIElement {
        QA.element(app, labelBeginsWith: prefix)
    }

    private func scrollUp(_ app: XCUIApplication, by fraction: CGFloat) {
        let scrollView = app.scrollViews.firstMatch
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8 - fraction))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
    }

    /// Scrolls until `element` sits in the middle of the screen.
    private func center(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        for _ in 0..<8 where element.frame.midY > app.frame.height * 0.55 {
            let before = element.frame
            scrollUp(app, by: min((element.frame.midY - app.frame.height * 0.45) / app.frame.height, 0.5))
            if element.frame == before { break }
        }
    }

    /// A screenshot plus the frame (points) of what it's for.
    private func capture(_ name: String, _ frame: CGRect) {
        QA.shot(name)
        QA.write(NSCoder.string(for: frame), to: "\(name)-frame.txt")
    }

    private func mark(_ name: String) {
        QA.write("\(Date().timeIntervalSince1970)", to: "\(name)-time.txt")
    }

    // MARK: - Captures

    func testDayHeroWithTheWhyLine() {
        let app = launchHome()
        let hero = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.hero'")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        QA.pause(4)
        XCTAssertTrue(QA.text(app, containing: "Mostly: sleep was").exists)
        capture("v3-day-hero", app.frame)
    }

    func testNightPanelRestScrubAndNoHeartRate() {
        let app = launchHome()
        let night = element(app, "Last night")
        let chart = element(app, "Sleep stages chart")
        center(chart, in: app)
        QA.pause(3.5)
        // The panel: its header through its totals, plus its 20pt padding.
        let panel = night.frame.union(chart.frame).insetBy(dx: -20, dy: -20)
        capture("v3-night-rest", panel)
        // A held sideways drag; the recording has the pill.
        let start = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.25))
        let end = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.25))
        mark("v3-scrub")
        QA.write(NSCoder.string(for: panel), to: "v3-scrub-frame.txt")
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 2)
        app.terminate()

        let sleepOnly = launchHome("sleepOnly")
        let quiet = element(sleepOnly, "Sleep stages chart")
        center(quiet, in: sleepOnly)
        QA.pause(3.5)
        let noHeart = element(sleepOnly, "Last night").frame.union(quiet.frame).insetBy(dx: -20, dy: -20)
        capture("v3-night-no-hr", noHeart)
    }

    func testEachInsightEvidenceType() {
        for (scenario, title) in [("full", "Shorter night"), ("lateBedtime", "Later bedtime"), ("steady", "Steady bedtime")] {
            let app = launchHome(scenario)
            let insight = element(app, title)
            center(insight, in: app)
            QA.pause(3.5)
            capture("v3-insight-\(scenario)", insight.frame)
            app.terminate()
        }
    }

    func testThisWeekAndTonight() {
        let app = launchHome()
        let tonight = element(app, "Tonight.")
        center(tonight, in: app)
        QA.pause(3.5)
        capture("v3-tonight", tonight.frame)
        let week = element(app, "This week")
        center(week, in: app)
        QA.pause(0.8)
        capture("v3-week-rest", week.frame)
        let frame = week.frame
        week.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 20 + (frame.width - 40) * 3.5 / 7, dy: 110)).tap()
        QA.pause(0.8)
        XCTAssertTrue(((week.value as? String) ?? "").contains(" · Deep "), (week.value as? String) ?? "")
        capture("v3-week-selected", week.frame.insetBy(dx: 0, dy: -34))
    }

    func testEveningOnTheEveningPaper() {
        let app = launchHome(mode: "evening")
        XCTAssertTrue(app.descendants(matching: .any)["home.eveningHero"].waitForExistence(timeout: 10))
        QA.pause(2)
        XCTAssertTrue(QA.text(app, containing: "Good evening").exists)
        capture("v3-evening", app.frame)
        scrollUp(app, by: 0.5)
        QA.pause(1)
        capture("v3-evening-2", app.frame)
    }

    func testLearningDots() {
        let app = launchHome("learning")
        XCTAssertTrue(QA.text(app, containing: "3 of 5 nights").waitForExistence(timeout: 10))
        QA.pause(1.5)
        capture("v3-learning", app.frame)
    }

    func testRecoveryDetailSparklines() {
        let app = launchHome()
        let hero = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.hero'")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        QA.pause(3.5)
        hero.tap()
        XCTAssertTrue(app.navigationBars["Recovery"].waitForExistence(timeout: 5))
        let hrv = element(app, "HRV ")
        XCTAssertTrue(hrv.waitForExistence(timeout: 5))
        XCTAssertTrue(hrv.label.contains("has been within your normal range on"), hrv.label)
        center(hrv, in: app)
        QA.pause(1)
        let rows = ["Sleep ", "HRV ", "Resting HR ", "Consistency "].map { element(app, $0) }.filter(\.exists)
        capture("v3-detail", rows.map(\.frame).reduce(rows[0].frame) { $0.union($1) }.insetBy(dx: 0, dy: -8))
    }

    func testShareCard() {
        let app = launchHome()
        let hero = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.hero'")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        QA.pause(3.5)
        hero.press(forDuration: 1.2)
        let share = app.buttons["Share today"]
        XCTAssertTrue(share.waitForExistence(timeout: 3))
        share.tap()
        let preview = app.images["home.share.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        QA.pause(0.8)
        capture("v3-share", preview.frame)
    }
}
