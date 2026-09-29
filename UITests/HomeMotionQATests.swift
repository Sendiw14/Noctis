import XCTest

/// Home v2 Part B (APP_RULES.md R11): the morning reveal, scroll collapse,
/// mode morph, night scrub, week selection, insight hiding, sharing and
/// the evening accessory. Transitions are captured from a screen
/// recording: each test writes when its gesture began (`*-time.txt`).
@MainActor
final class HomeMotionQATests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// A failed VoiceOver test must not leave VoiceOver on for the next.
    override func tearDown() {
        if #available(iOS 27.0, *), XCUIDevice.shared.voiceOverService.isEnabled {
            try? XCUIDevice.shared.voiceOverService.disable()
        }
        super.tearDown()
    }

    private func launchHome(mode: String = "day", extra: [String] = [], reset: Bool = true) -> XCUIApplication {
        QA.launch(extra: ["-useMockHealth", "-mockScenario", "full", "-noctisSkipOnboarding", "-homeMode", mode] + extra, reset: reset)
    }

    private func mark(_ name: String) {
        QA.write("\(Date().timeIntervalSince1970)", to: "\(name)-time.txt")
    }

    private func element(_ app: XCUIApplication, _ prefix: String) -> XCUIElement {
        QA.element(app, labelBeginsWith: prefix)
    }

    /// Drags the scroll view up from its side margin (no card gestures).
    private func scrollUp(_ app: XCUIApplication, by fraction: CGFloat = 0.55) {
        let scrollView = app.scrollViews.firstMatch
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85 - fraction))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// Scrolls until `element` sits fully on screen (or Home can't
    /// scroll further).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        var attempts = 0
        while !element.isHittable || element.frame.maxY > app.frame.maxY - 120, attempts < 8 {
            let before = element.frame
            scrollUp(app, by: 0.3)
            attempts += 1
            if element.frame == before { break }
        }
    }

    /// "Mon": the weekday of last night's morning, or `daysAgo` before it
    /// (This week's bars are labeled by the morning each night ended). The
    /// mock's last night ends this morning once it's 9 AM, yesterday's
    /// morning before that.
    private func weekday(daysAgo: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE"
        let lastMorning = Calendar.current.component(.hour, from: Date()) >= 9 ? 0 : 1
        return formatter.string(from: Date().addingTimeInterval(-Double(daysAgo + lastMorning) * 86_400))
    }

    private func dayHero(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.hero'")).firstMatch
    }

    private func eveningHero(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["home.eveningHero"]
    }

    /// The tab bar minimizes as Home scrolls, so "Sleep is showing" is
    /// read from the Sleep tab's own range control.
    private func sleepIsShowing(_ app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)["sleep.range"].waitForExistence(timeout: 2)
    }

    // MARK: - Morning reveal

    func testMorningRevealRunsOncePerDay() {
        mark("reveal-launch")
        let app = launchHome()
        XCTAssertTrue(app.buttons["home.hero.revealed"].waitForExistence(timeout: 10), "The first day-mode Home of the day plays the reveal.")
        QA.pause(3)
        QA.shot("reveal-end")
        app.terminate()

        // Same day, no reset: straight to the end state.
        let again = launchHome(reset: false)
        XCTAssertTrue(again.buttons["home.hero"].waitForExistence(timeout: 10))
        QA.pause(1)
        XCTAssertFalse(again.buttons["home.hero.revealed"].exists, "The reveal runs once per calendar day.")
    }

    // MARK: - Scroll collapse

    func testScrollCollapseShowsTheCompactBar() {
        let app = launchHome()
        let hero = dayHero(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        QA.pause(3.5)
        let bar = app.buttons["home.collapsedBar"]
        XCTAssertFalse(bar.exists)
        mark("collapse-scroll")
        scrollUp(app, by: 0.15)
        QA.pause(0.4)
        XCTAssertFalse(bar.exists, "Not yet 70% past.")
        for _ in 0..<4 where !bar.exists {
            scrollUp(app, by: 0.3)
            QA.pause(0.4)
        }
        XCTAssertTrue(bar.waitForExistence(timeout: 3))
        XCTAssertTrue(bar.label.hasPrefix("Recovery "), bar.label)
        XCTAssertTrue(bar.label.hasSuffix("Scroll to top"), bar.label)
        QA.pause(0.5)
        QA.shot("collapsed-bar-day")
        mark("collapse-tap")
        bar.tap()
        QA.pause(1)
        XCTAssertFalse(bar.exists, "Tapping the bar returns to the top.")
        XCTAssertTrue(hero.isHittable)
    }

    func testScrollCollapseInTheEvening() {
        let app = launchHome(mode: "evening")
        XCTAssertTrue(eveningHero(app).waitForExistence(timeout: 10))
        QA.pause(1)
        scrollUp(app, by: 0.5)
        let bar = app.buttons["home.collapsedBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 3))
        XCTAssertTrue(bar.label.hasPrefix("Bedtime "), bar.label)
        QA.pause(0.5)
        QA.shot("collapsed-bar-evening")
    }

    // MARK: - Mode morph

    func testModeMorphDayToEvening() {
        let app = launchHome(extra: ["-homeModeFlipIn", "6"])
        let hero = dayHero(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        mark("morph-armed")
        XCTAssertFalse(eveningHero(app).exists)
        // The evening hero replaces the ring, and the ring becomes the compact card.
        XCTAssertTrue(eveningHero(app).waitForExistence(timeout: 12))
        QA.pause(1.5)
        XCTAssertFalse(hero.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recovery '")).firstMatch.exists)
        QA.shot("morph-evening")
    }

    func testModeMorphEveningToDay() {
        let app = launchHome(mode: "evening", extra: ["-homeModeFlipIn", "6"])
        XCTAssertTrue(eveningHero(app).waitForExistence(timeout: 10))
        mark("morph-back-armed")
        let hero = dayHero(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 12))
        QA.pause(1.5)
        XCTAssertFalse(eveningHero(app).exists)
        QA.shot("morph-day")
    }

    // MARK: - Night panel

    func testNightScrubDragsWithoutOpeningSleep() {
        let app = launchHome()
        let panel = element(app, "Last night")
        let chart = element(app, "Sleep stages chart")
        reveal(chart, in: app)
        QA.pause(3)
        // A real sideways drag across the chart, held so the recording
        // shows the line, the dot and the pill.
        let start = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
        let end = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.4))
        mark("scrub")
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.5)
        QA.pause(0.5)
        XCTAssertFalse(sleepIsShowing(app), "A drag scrubs; it doesn't open Sleep.")
        XCTAssertTrue(panel.isHittable)
        // A plain tap still opens Sleep.
        panel.tap()
        XCTAssertTrue(sleepIsShowing(app))
    }

    /// VoiceOver's adjustable actions read the pill's text, one stage
    /// segment per swipe, and step through the week's bars. Each element
    /// is brought on screen with VoiceOver off, then focused with a tap.
    func testVoiceOverStepsThroughTheNightAndTheWeek() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("XCUIVoiceOverService needs iOS 27") }
        let app = launchHome()
        let panel = element(app, "Last night")
        reveal(panel, in: app)
        QA.pause(3.5)
        let voiceOver = XCUIDevice.shared.voiceOverService
        // VoiceOver hears the pill in words: "3:41 AM, REM, 47 minutes, 52 beats per minute".
        let pill = try NSRegularExpression(pattern: #"\d{1,2}:\d{2}\s?[AP]M, (Awake|REM|Core|Deep|Asleep), \d+ (hour|hours|minute|minutes)"#)
        let bar = try NSRegularExpression(pattern: #"(Mon|Tue|Wed|Thu|Fri|Sat|Sun) · (\d+h( \d+m)?|\d+m|No data)"#)
        func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
            regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        func speech() -> String {
            ((try? voiceOver.currentSpeech())?.utterance ?? "").replacingOccurrences(of: "\u{202F}", with: " ")
        }
        /// Focus `element` (VoiceOver's single tap), then swipe up `count` times.
        func adjust(_ element: XCUIElement, _ count: Int) throws -> (focus: String, values: [String]) {
            try voiceOver.enable()
            QA.pause(1.5)
            element.tap()
            QA.pause(1.5)
            let focus = speech()
            var values: [String] = []
            for _ in 0..<count {
                app.swipeUp()
                QA.pause(1)
                values.append(speech())
            }
            try voiceOver.disable()
            QA.pause(1)
            return (focus, values)
        }

        let night = try adjust(panel, 4)
        let card = element(app, "This week")
        reveal(card, in: app)
        QA.pause(0.5)
        let week = try adjust(card, 2)
        QA.write((["-- night", night.focus] + night.values + ["-- week", week.focus] + week.values).joined(separator: "\n"), to: "voiceover-home.txt")
        XCTAssertTrue(night.focus.hasPrefix("Last night"), night.focus)
        XCTAssertTrue(night.values.allSatisfy { matches(pill, $0) }, "\(night.values)")
        XCTAssertEqual(Set(night.values).count, night.values.count, "Each swipe moves to the next segment: \(night.values)")
        XCTAssertTrue(week.focus.hasPrefix("This week"), week.focus)
        XCTAssertTrue(week.values.allSatisfy { matches(bar, $0) }, "\(week.values)")
    }

    func testNightPanelContextMenu() {
        let app = launchHome()
        let panel = element(app, "Last night")
        reveal(panel, in: app)
        QA.pause(3)
        panel.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Share this night"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open Sleep"].exists)
        QA.pause(0.6)
        QA.shot("context-night")
        app.buttons["Open Sleep"].tap()
        XCTAssertTrue(sleepIsShowing(app))
    }

    // MARK: - This week

    func testWeekBarSelection() {
        let app = launchHome()
        let card = element(app, "This week")
        reveal(card, in: app)
        QA.pause(3)
        let frame = card.frame
        let origin = card.coordinate(withNormalizedOffset: .zero)
        // The bars sit 20pt inside the card, below its caption row.
        let chartWidth = frame.width - 40
        let lastBar = origin.withOffset(CGVector(dx: 20 + chartWidth * 6.5 / 7, dy: 20 + 30 + 60))
        mark("week-select")
        lastBar.tap()
        QA.pause(0.6)
        QA.shot("week-tapped")
        let value = (card.value as? String) ?? ""
        XCTAssertTrue(value.hasPrefix("\(weekday(daysAgo: 0)) · "), value)
        XCTAssertTrue(value.contains(" · Deep ") && value.contains(" · REM "), "Last night had stages: \(value)")
        QA.write(value, to: "week-selected.txt")
        QA.shot("week-selected")
        XCTAssertFalse(sleepIsShowing(app), "A bar tap selects; it doesn't open Sleep.")
        lastBar.tap()
        QA.pause(0.6)
        XCTAssertEqual((card.value as? String) ?? "", "", "Tapping the bar again clears it.")
        // The outer columns run out through the card's padding, and past
        // it into the screen margin: 8pt inside the card, and 8pt outside
        // it, both select the first night; 8pt outside the right edge
        // selects the last.
        for dx in [CGFloat(8), CGFloat(-8)] {
            origin.withOffset(CGVector(dx: dx, dy: 20 + 30 + 60)).tap()
            QA.pause(0.6)
            XCTAssertTrue(((card.value as? String) ?? "").hasPrefix("\(weekday(daysAgo: 6)) · "), "dx \(dx): \((card.value as? String) ?? "")")
            origin.withOffset(CGVector(dx: dx, dy: 20 + 30 + 60)).tap()
            QA.pause(0.4)
        }
        origin.withOffset(CGVector(dx: frame.width + 8, dy: 20 + 30 + 60)).tap()
        QA.pause(0.6)
        XCTAssertTrue(((card.value as? String) ?? "").hasPrefix("\(weekday(daysAgo: 0)) · "), (card.value as? String) ?? "")
        QA.write("card=\(NSCoder.string(for: frame)) column=\((frame.width) / 7)", to: "week-columns.txt")
    }

    /// Lane labels answer taps a little beyond their 28pt lanes: 44pt tall.
    func testLaneLabelTargetsAre44PointsTall() {
        let app = launchHome()
        let header = element(app, "Last night")
        let chart = element(app, "Sleep stages chart")
        reveal(chart, in: app)
        QA.pause(3)
        // The lanes start 16pt below the header (the chart element's own
        // frame also holds the invisible scrub pill above them).
        let lanesTop = header.frame.maxY + 16
        let x = chart.frame.minX + 16
        let origin = app.coordinate(withNormalizedOffset: .zero)
        QA.write("header=\(NSCoder.string(for: header.frame)) chart=\(NSCoder.string(for: chart.frame)) lanesTop=\(lanesTop)", to: "lane-targets.txt")
        // 6pt above the Awake lane: outside the lane, inside its 44pt target.
        origin.withOffset(CGVector(dx: x, dy: lanesTop - 6)).tap()
        QA.pause(0.6)
        XCTAssertTrue(((chart.value as? String) ?? "").hasPrefix("Awake · "), (chart.value as? String) ?? "")
        QA.shot("lane-focused")
        // Tapping it again clears.
        origin.withOffset(CGVector(dx: x, dy: lanesTop + 10)).tap()
        QA.pause(0.6)
        XCTAssertEqual((chart.value as? String) ?? "", "")
        // 6pt below the Deep lane (lane 4 ends 112pt down): the same reach.
        origin.withOffset(CGVector(dx: x, dy: lanesTop + 112 + 6)).tap()
        QA.pause(0.6)
        XCTAssertTrue(((chart.value as? String) ?? "").hasPrefix("Deep · "), (chart.value as? String) ?? "")
    }

    // MARK: - Insight fatigue

    func testHidingAnInsightSticks() {
        let app = launchHome()
        let insight = element(app, "Shorter night than usual")
        reveal(insight, in: app)
        QA.pause(3)
        insight.press(forDuration: 1.2)
        let hide = app.buttons["Hide insights like this"]
        XCTAssertTrue(hide.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Not useful"].exists)
        QA.shot("context-insight")
        mark("insight-hide")
        hide.tap()
        // The menu closes (0.5s), then the block collapses.
        QA.pause(1.6)
        XCTAssertFalse(insight.exists, "The block collapses.")
        QA.shot("insight-hidden")
        app.terminate()

        let again = launchHome(reset: false)
        XCTAssertTrue(dayHero(again).waitForExistence(timeout: 10))
        QA.pause(1)
        XCTAssertFalse(element(again, "Shorter night than usual").exists, "Hidden stays hidden.")
    }

    // MARK: - Share

    func testShareTodayRendersTheCard() {
        let app = launchHome()
        let hero = dayHero(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        QA.pause(3.5)
        hero.press(forDuration: 1.2)
        let share = app.buttons["Share today"]
        XCTAssertTrue(share.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open Recovery"].exists)
        QA.pause(0.6)
        QA.shot("context-ring")
        share.tap()
        let preview = app.images["home.share.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share"].exists)
        QA.pause(0.8)
        QA.shot("share-sheet")
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.exists)
        XCTAssertEqual(toggle.value as? String, "0", "Details are off by default.")
        toggle.switches.firstMatch.tap()
        QA.pause(0.8)
        XCTAssertEqual(toggle.value as? String, "1")
        QA.shot("share-sheet-details")
        app.buttons["Close"].tap()
    }

    // MARK: - Evening accessory

    func testEveningAccessoryOnEveryTab() {
        let app = launchHome(mode: "evening")
        let accessory = app.buttons["home.bedtimeAccessory"]
        XCTAssertTrue(accessory.waitForExistence(timeout: 10))
        XCTAssertTrue(accessory.label.hasPrefix("Bedtime "), accessory.label)
        QA.pause(1)
        QA.shot("accessory-home")
        app.tabBars.buttons["Sleep"].tap()
        XCTAssertTrue(accessory.waitForExistence(timeout: 3))
        QA.pause(0.6)
        QA.shot("accessory-sleep")
        accessory.tap()
        QA.pause(0.6)
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
    }

    func testNoAccessoryByDay() {
        let app = launchHome()
        XCTAssertTrue(dayHero(app).waitForExistence(timeout: 10))
        QA.pause(1)
        XCTAssertFalse(app.buttons["home.bedtimeAccessory"].exists)
    }
}
