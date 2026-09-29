import XCTest

/// Home v4, part 2 (APP_RULES.md R11, R23): interruptions, the saved
/// snapshot, the minute tick, memory, and hitch/signpost measurements.
///
/// XCTest waits for the app to be idle before it sends an event, so a tap
/// can't be aimed at the middle of an animation. Each interruption test
/// therefore puts a gesture *across* the moment the animation starts (a
/// drag begun at launch, a slow drag over a timed mode flip), or checks
/// the state right after a fast pair of gestures. The mid-animation
/// cases are covered again by unit tests of the state machines and by the
/// simulator control tool in the QA notes.
///
/// The numbers these tests print come from the simulator: they are smoke
/// tests, never the device budgets (hitch time ratio < 5 ms/s, 120 fps,
/// cold launch < 400 ms to the first frame and < 1.2 s populated, no
/// memory growth), which need a physical iPhone.
@MainActor
final class HomePerformanceQATests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchHome(
        mode: String = "day", scenario: String = "full", extra: [String] = [], reset: Bool = true
    ) -> XCUIApplication {
        QA.launch(
            extra: ["-useMockHealth", "-mockScenario", scenario, "-noctisSkipOnboarding", "-homeMode", mode] + extra,
            reset: reset
        )
    }

    private func dayHero(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.hero'")).firstMatch
    }

    private func eveningHero(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["home.eveningHero"]
    }

    /// Drags the page up (content scrolls down the page) by `fraction` of
    /// its height, from the side margin (no card gestures).
    private func scrollUp(_ app: XCUIApplication, by fraction: CGFloat, hold: Double = 0.3) {
        let scrollView = app.scrollViews.firstMatch
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85 - fraction))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: hold)
    }

    /// The other way: back toward the top.
    private func scrollDown(_ app: XCUIApplication, by fraction: CGFloat, hold: Double = 0.3) {
        let scrollView = app.scrollViews.firstMatch
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.25))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.25 + fraction))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: hold)
    }

    /// The probe's report: "HomeContent=2;HomeView=3;…" and the footprint.
    private func probe(_ app: XCUIApplication) -> (counts: [String: Int], megabytes: Double) {
        let element = app.descendants(matching: .any)["debug.probe"]
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Launch with -noctisDebugProbe.")
        let counts = element.label.split(separator: ";").reduce(into: [String: Int]()) { result, pair in
            let parts = pair.split(separator: "=")
            if parts.count == 2, let value = Int(parts[1]) { result[String(parts[0])] = value }
        }
        return (counts, Double(element.value as? String ?? "") ?? 0)
    }

    private func mark(_ name: String) {
        QA.write("\(Date().timeIntervalSince1970)", to: "\(name)-time.txt")
    }

    // MARK: - Ring, Low Power Mode and Reduce Motion

    /// Tapping a capsule dims the other segments to 40% (a spring on the
    /// ring's dim value, 0.4s) before Recovery opens on that factor: the
    /// recording shows it.
    func testCapsuleHighlightDimsTheOtherSegments() {
        let app = launchHome()
        XCTAssertTrue(dayHero(app).waitForExistence(timeout: 10))
        QA.pause(3.5)
        let capsule = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'HRV'")).firstMatch
        XCTAssertTrue(capsule.waitForExistence(timeout: 3))
        mark("capsule-tap")
        capsule.tap()
        XCTAssertTrue(app.navigationBars["Recovery"].waitForExistence(timeout: 4))
        QA.pause(1)
    }

    /// Low Power Mode (forced; the simulator can't turn it on): the reveal
    /// still draws the ring and the night, but the score shows its end
    /// state from the first frame and the capsules and bars arrive together.
    func testLowPowerModeRevealShowsTheEndStates() {
        mark("lowpower-launch")
        let app = launchHome(extra: ["-noctisLowPowerMode", "-noctisDebugProbe"])
        XCTAssertTrue(app.buttons["home.hero.revealed"].waitForExistence(timeout: 10), "The reveal still plays.")
        XCTAssertEqual(probe(app).counts["lowPower"], 1, "Low Power Mode is on.")
        QA.pause(3.2)
        QA.shot("lowpower-end")
        XCTAssertTrue(dayHero(app).label.hasPrefix("Recovery "))
    }

    /// Reduce Motion: no reveal at all, the end state at the first frame
    /// (run with Reduce Motion on in the simulator).
    func testReduceMotionShowsTheEndStateAtOnce() throws {
        let app = launchHome()
        let hero = dayHero(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        try XCTSkipIf(app.buttons["home.hero.revealed"].waitForExistence(timeout: 2), "Reduce Motion is off")
        QA.pause(0.4)
        QA.shot("reduce-motion-first-frames")
        XCTAssertTrue(hero.label.hasPrefix("Recovery "))
    }

    // MARK: - Interruptions

    /// A finger down while the morning reveal is starting cuts it to its
    /// end state at once: the ring is full and the score is final, nothing
    /// is left mid-draw, and Home stays usable.
    func testATouchAtLaunchCutsTheRevealShort() {
        let app = launchHome()
        // A slow drag begun as soon as the app is up: it is on the screen
        // when the reveal starts (the skeleton's 0.3s, then the dusk).
        scrollUp(app, by: 0.1, hold: 0.2)
        let hero = dayHero(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        QA.pause(0.8)
        // Well before the reveal's ~2.5s would have ended, it has.
        QA.shot("interrupt-reveal")
        XCTAssertTrue(hero.label.hasPrefix("Recovery "), hero.label)
        XCTAssertTrue(hero.isHittable)
        // Home takes input straight away: the ring opens Recovery.
        hero.tap()
        XCTAssertTrue(app.navigationBars["Recovery"].waitForExistence(timeout: 4))
    }

    /// A scroll that runs across the day → evening morph: the morph
    /// finishes underneath the finger, the page keeps the scroll, and the
    /// evening layout is the one that ends up on screen.
    func testScrollingAcrossTheModeMorph() {
        let app = launchHome(extra: ["-homeModeFlipIn", "4"])
        let hero = dayHero(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        QA.pause(1.5)
        let panel = QA.element(app, labelBeginsWith: "Last night")
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let before = panel.frame.minY
        // A slow drag of half the screen, a few seconds long, begun about
        // 2.5s in: the flip (at 4s) lands in the middle of it.
        let scrollView = app.scrollViews.firstMatch
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(eveningHero(app).waitForExistence(timeout: 6), "The morph completed.")
        QA.pause(1)
        QA.shot("interrupt-morph")
        XCTAssertFalse(dayHero(app).exists)
        XCTAssertNotEqual(QA.element(app, labelBeginsWith: "Last night").frame.minY, before, "The page moved.")
        // The scroll kept going through the morph: the hero has collapsed
        // into the compact bar.
        XCTAssertTrue(app.buttons["home.collapsedBar"].waitForExistence(timeout: 3))
        // Still interactive: back at the top the evening hero is there.
        for _ in 0..<3 where !eveningHero(app).isHittable { scrollDown(app, by: 0.5) }
        XCTAssertTrue(eveningHero(app).exists)
    }

    /// Open Recovery, go back by the edge swipe the moment it is up, and
    /// open it again: the zoom has no state to get stuck in.
    func testBackSwipeAfterTheRecoveryZoomAndZoomingAgain() {
        let app = launchHome()
        let hero = dayHero(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        QA.pause(3)
        for round in 1...3 {
            hero.tap()
            XCTAssertTrue(app.navigationBars["Recovery"].waitForExistence(timeout: 4), "Round \(round) opens.")
            // The interactive back swipe from the left edge.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
            XCTAssertTrue(hero.waitForExistence(timeout: 4), "Round \(round) comes back.")
            XCTAssertFalse(app.navigationBars["Recovery"].exists, "Round \(round) left Recovery.")
            XCTAssertTrue(hero.isHittable)
        }
        QA.shot("interrupt-zoom")
    }

    // MARK: - The saved snapshot

    /// With Health slow to answer (8 s per query), a second launch has
    /// content in its first frames from the snapshot the first one saved;
    /// a launch with nothing saved shows the skeleton.
    func testColdLaunchDrawsTheSavedSnapshotBeforeHealthAnswers() {
        // Launch 1 saves.
        let first = launchHome(extra: ["-noctisSnapshotCache"])
        XCTAssertTrue(dayHero(first).waitForExistence(timeout: 10))
        QA.pause(3)
        first.terminate()

        // Launch 2, slow Health: the score is on screen at once.
        let second = launchHome(extra: ["-noctisSnapshotCache", "-mockLatency", "8"], reset: false)
        let hero = dayHero(second)
        XCTAssertTrue(hero.waitForExistence(timeout: 3), "The saved snapshot is drawn before Health answers.")
        XCTAssertTrue(hero.label.hasPrefix("Recovery "), hero.label)
        XCTAssertFalse(second.descendants(matching: .any)["Loading your sleep data"].exists, "No skeleton.")
        QA.shot("cold-launch-restored")
        second.terminate()

        // Launch 3, reset (which erases it), slow Health: the skeleton.
        let third = launchHome(extra: ["-noctisSnapshotCache", "-mockLatency", "8"])
        XCTAssertTrue(third.descendants(matching: .any)["Loading your sleep data"].waitForExistence(timeout: 5))
        XCTAssertFalse(dayHero(third).exists)
    }

    // MARK: - The minute tick

    /// A minute passes: the evening countdown changes, and Home's root and
    /// its cards don't evaluate their bodies again.
    func testAMinuteTickReEvaluatesTheCountdownAndNoRootView() throws {
        let app = launchHome(mode: "evening", extra: ["-noctisDebugProbe"])
        let hero = eveningHero(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        try XCTSkipUnless(hero.label.contains(", in "), "Past bedtime the countdown doesn't tick: \(hero.label)")
        QA.pause(2)
        let before = probe(app)
        let labelBefore = hero.label
        // Wait for the next minute boundary, and a moment after it.
        let now = Date().timeIntervalSince1970
        let wait = 60 - now.truncatingRemainder(dividingBy: 60) + 3
        QA.pause(wait)
        let after = probe(app)
        XCTAssertNotEqual(eveningHero(app).label, labelBefore, "The countdown moved on.")
        QA.write("before \(before.counts)\nafter \(after.counts)", to: "minute-tick-probe.txt")
        for root in ["HomeView", "HomeContent", "NightPanel", "WeekCard", "HomeTopOverlay"] {
            XCTAssertEqual(after.counts[root], before.counts[root], "\(root) re-evaluated on the minute tick.")
        }
        XCTAssertGreaterThan(after.counts["EveningCountdown", default: 0], before.counts["EveningCountdown", default: 0])
    }

    // MARK: - Memory

    /// 20 tab switches and 5 Recovery zoom open/close cycles: the app's
    /// footprint doesn't grow. (Simulator smoke test; the budget is on a
    /// device.)
    func testNoMemoryGrowthAfterTabSwitchesAndZoomCycles() {
        let app = launchHome(extra: ["-noctisDebugProbe"])
        let hero = dayHero(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        QA.pause(4)
        // One warm-up lap, so lazily-built things exist before the baseline.
        app.tabBars.buttons["Sleep"].tap()
        app.tabBars.buttons["Home"].tap()
        QA.pause(1.5)
        let baseline = probe(app).megabytes
        for _ in 0..<10 {
            app.tabBars.buttons["Sleep"].tap()
            app.tabBars.buttons["Home"].tap()
        }
        for _ in 0..<5 {
            hero.tap()
            XCTAssertTrue(app.navigationBars["Recovery"].waitForExistence(timeout: 4))
            app.navigationBars["Recovery"].buttons.firstMatch.tap()
            XCTAssertTrue(hero.waitForExistence(timeout: 4))
        }
        QA.pause(3)
        let after = probe(app).megabytes
        QA.write("baseline \(baseline) MB, after \(after) MB", to: "memory.txt")
        XCTAssertLessThan(after - baseline, 15, "Footprint grew from \(baseline) to \(after) MB.")
    }

    // MARK: - Hitches and signposts

    /// The measurements for a scroll and the reveal. On a device they carry
    /// `XCTHitchMetric` (hitch time ratio); on the simulator, where the
    /// hitch metric isn't available, the app's own signpost intervals
    /// (`Collapse`, `Reveal`) and clock time stand in. Set a baseline on a
    /// device to turn them into a gate.
    private func metrics(_ app: XCUIApplication, signpost name: String) -> [XCTMetric] {
        var metrics: [XCTMetric] = [
            XCTOSSignpostMetric(subsystem: "com.noctis.app", category: "Performance", name: name),
            XCTClockMetric(),
        ]
        #if !targetEnvironment(simulator)
        if #available(iOS 18.0, *) { metrics.append(XCTHitchMetric(application: app)) }
        #endif
        return metrics
    }

    func testScrollHitches() {
        let app = launchHome(extra: ["-noctisSnapshotCache"])
        XCTAssertTrue(dayHero(app).waitForExistence(timeout: 10))
        QA.pause(4)
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: metrics(app, signpost: "Collapse"), options: options) {
            for _ in 0..<3 { scrollUp(app, by: 0.5, hold: 0) }
            for _ in 0..<3 { scrollDown(app, by: 0.5, hold: 0) }
        }
    }

    func testRevealHitches() {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStop]
        let app = XCUIApplication()
        // A reset each launch is a fresh day, so the reveal plays.
        app.launchArguments = ["-noctisResetState", "-useMockHealth", "-mockScenario", "full", "-noctisSkipOnboarding", "-homeMode", "day"]
        measure(metrics: metrics(app, signpost: "Reveal"), options: options) {
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["home.hero.revealed"].waitForExistence(timeout: 10))
            QA.pause(HomeRevealBudget.seconds)
            stopMeasuring()
        }
        app.terminate()
    }

    func testTabSwitchAndScrubSignposts() {
        let app = launchHome()
        XCTAssertTrue(dayHero(app).waitForExistence(timeout: 10))
        QA.pause(4)
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: metrics(app, signpost: "TabSwitch"), options: options) {
            app.tabBars.buttons["Sleep"].tap()
            app.tabBars.buttons["Home"].tap()
        }
    }
}

/// How long the reveal takes to play out, with room (HomeReveal's total).
private enum HomeRevealBudget {
    static let seconds = 3.2
}
