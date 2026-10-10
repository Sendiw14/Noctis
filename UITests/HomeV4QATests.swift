import XCTest

/// Home v4 (APP_RULES.md R11): the sleep landscape, the ring's usual
/// ticks, the week scrub, and the small fixes. Captures write the frame
/// they show (`<name>-frame.txt`, points) so they can be cropped at full
/// resolution.
@MainActor
final class HomeV4QATests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        if #available(iOS 27.0, *), XCUIDevice.shared.voiceOverService.isEnabled {
            try? XCUIDevice.shared.voiceOverService.disable()
        }
        try await super.tearDown()
    }

    private func launchHome(_ scenario: String = "full", mode: String = "day", extra: [String] = []) -> XCUIApplication {
        QA.launch(extra: ["-useMockHealth", "-mockScenario", scenario, "-noctisSkipOnboarding", "-homeMode", mode] + extra)
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

    private func capture(_ name: String, _ frame: CGRect) {
        QA.shot(name)
        QA.write(NSCoder.string(for: frame), to: "\(name)-frame.txt")
    }

    private func mark(_ name: String) {
        QA.write("\(Date().timeIntervalSince1970)", to: "\(name)-time.txt")
    }

    /// The mock's last night ends this morning once it's 9 AM, yesterday's
    /// morning before that.
    private func weekday(daysAgo: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE"
        let lastMorning = Calendar.current.component(.hour, from: Date()) >= 9 ? 0 : 1
        return formatter.string(from: Date().addingTimeInterval(-Double(daysAgo + lastMorning) * 86_400))
    }

    // MARK: - Sleep landscape

    func testLandscapeOnAMessyNight() {
        let app = launchHome("messyNight")
        let header = element(app, "Last night")
        let chart = element(app, "Sleep stages chart")
        center(chart, in: app)
        QA.pause(3.5)
        // The panel: its header through its totals, plus its 20pt padding.
        let panel = header.frame.union(chart.frame).insetBy(dx: -20, dy: -20)
        capture("v4-messy-rest", panel)
        // A held sideways drag; the recording has the pill.
        let lanesTop = header.frame.maxY + 16
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: chart.frame.minX + 80, dy: lanesTop + 60))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: chart.frame.minX + 190, dy: lanesTop + 60))
        mark("v4-messy-scrub")
        QA.write(NSCoder.string(for: panel), to: "v4-messy-scrub-frame.txt")
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 2)
        QA.pause(0.5)
        // Tapping a lane label highlights that stage and shows its total.
        // (Lanes scale with the text size, so the fixed 28pt offsets below
        // only hold at the default size.)
        guard !QA.isAX3 else { return }
        let x = chart.frame.minX + 16
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: lanesTop + 28 * 3 + 14)).tap()
        QA.pause(0.7)
        XCTAssertTrue(((chart.value as? String) ?? "").hasPrefix("Deep · "), (chart.value as? String) ?? "")
        capture("v4-messy-deep", panel)
    }

    func testTheLandscapeOnTheRealNightAndWithoutHeartRate() {
        let app = launchHome()
        let header = element(app, "Last night")
        let chart = element(app, "Sleep stages chart")
        center(chart, in: app)
        QA.pause(3.5)
        capture("v4-landscape-rest", header.frame.union(chart.frame).insetBy(dx: -20, dy: -20))
        app.terminate()

        let sleepOnly = launchHome("sleepOnly")
        let quiet = element(sleepOnly, "Sleep stages chart")
        center(quiet, in: sleepOnly)
        QA.pause(3.5)
        capture("v4-landscape-no-hr", element(sleepOnly, "Last night").frame.union(quiet.frame).insetBy(dx: -20, dy: -20))
    }

    // MARK: - Ring ticks

    func testRingTicksAndTheirCaption() {
        let app = launchHome()
        let hero = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.hero'")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        QA.pause(4)
        XCTAssertTrue(QA.text(app, containing: "Tick = your usual").exists)
        let sleep = app.buttons.matching(NSPredicate(format: "label MATCHES 'Sleep \\\\d+, usual \\\\d+'")).firstMatch
        XCTAssertTrue(sleep.exists, "The capsule reads its usual aloud.")
        capture("v4-ring-ticks", app.frame)
        QA.write(sleep.label, to: "v4-capsule-label.txt")
    }

    // MARK: - This week

    func testWeekScrubFollowsTheFingerAndStays() {
        let app = launchHome()
        let card = element(app, "This week")
        center(card, in: app)
        QA.pause(3.5)
        capture("v4-week-rest", card.frame)
        let origin = card.coordinate(withNormalizedOffset: .zero)
        let y: CGFloat = 20 + 30 + 60
        let frame = card.frame
        // Drag from the first bar to the last: the selection follows.
        let start = origin.withOffset(CGVector(dx: 20 + (frame.width - 40) * 0.5 / 7, dy: y))
        let end = origin.withOffset(CGVector(dx: 20 + (frame.width - 40) * 6.5 / 7, dy: y))
        let middle = origin.withOffset(CGVector(dx: 20 + (frame.width - 40) * 3.5 / 7, dy: y))
        mark("v4-week-scrub")
        start.press(forDuration: 0.05, thenDragTo: middle, withVelocity: .slow, thenHoldForDuration: 0.6)
        QA.pause(0.4)
        let midValue = (card.value as? String) ?? ""
        XCTAssertTrue(midValue.hasPrefix("\(weekday(daysAgo: 3)) · "), midValue)
        capture("v4-week-scrub-mid", card.frame.insetBy(dx: 0, dy: -34))
        middle.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
        QA.pause(0.4)
        // Lifting leaves the last night selected.
        let endValue = (card.value as? String) ?? ""
        XCTAssertTrue(endValue.hasPrefix("\(weekday(daysAgo: 0)) · "), endValue)
        QA.pause(1)
        XCTAssertEqual((card.value as? String) ?? "", endValue, "The last selection stays.")
        capture("v4-week-scrub-end", card.frame.insetBy(dx: 0, dy: -34))
        // Tapping the selected night clears it.
        end.tap()
        QA.pause(0.6)
        XCTAssertEqual((card.value as? String) ?? "", "")
        // A tap on another night selects it.
        start.tap()
        QA.pause(0.6)
        XCTAssertTrue(((card.value as? String) ?? "").hasPrefix("\(weekday(daysAgo: 6)) · "), (card.value as? String) ?? "")
    }

    // MARK: - Small fixes

    func testEveningGreetingChangesAtMidnight() {
        let app = launchHome(mode: "evening")
        XCTAssertTrue(app.descendants(matching: .any)["home.eveningHero"].waitForExistence(timeout: 10))
        QA.pause(2)
        let hour = Calendar.current.component(.hour, from: Date())
        let expected = hour < 4 ? "Good night" : "Good evening"
        XCTAssertTrue(QA.text(app, containing: expected).exists, "at \(hour):00")
        capture("v4-greeting-\(hour < 4 ? "night" : "evening")", app.frame)
    }

    func testTheStreakSaysWhichNights() {
        let app = launchHome("steady")
        let insight = element(app, "Steady bedtime")
        center(insight, in: app)
        QA.pause(3.5)
        // Read as a whole: the dots are in the label ("… 5 of the last 7 nights").
        XCTAssertTrue(insight.label.contains("last 7 nights"), insight.label)
        capture("v4-streak", insight.frame)
    }
}
