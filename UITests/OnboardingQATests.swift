import XCTest

/// Onboarding QA (ONBOARDING_RULES.md R11). `testScreenMatrix` runs on every
/// device/text-size combination; the state and flow tests run once.
@MainActor
final class OnboardingQATests: XCTestCase {
    private let goals = "betterSleep,moreEnergy"

    // MARK: - Every screen, every page

    func testScreenMatrix() {
        let screens: [(name: String, step: String, goals: String?, settle: Double)] = [
            ("01-welcome", "welcome", nil, 2.5),
            ("02-goal", "goal", nil, 2),
            ("03-rhythm", "rhythm", goals, 2),
            ("04-sample", "sample", goals, 3),
            ("05-health", "health", goals, 2.5),
            ("06-notifications", "notifications", goals, 2.5),
            ("08-plan", "plan", goals, 5),
            ("09-paywall", "paywall", goals, 5),
        ]
        for screen in screens {
            let app = QA.launch(step: screen.step, goals: screen.goals)
            if screen.step == "plan" {
                QA.shot("07-plan-building")
            }
            QA.pause(screen.settle)
            // Stuck-animation check (compared off-device, outside the status
            // bar): two frames 2s apart, before anything scrolls.
            QA.shot("\(screen.name)-still-a")
            QA.pause(2)
            QA.shot("\(screen.name)-still-b")
            QA.inspect(app, screen.name)
            QA.capturePages(app, screen.name)
            app.terminate()
        }
    }

    // MARK: - States

    func testGoalSelectionStates() {
        let app = QA.launch(step: "goal")
        QA.pause(1.5)
        let sleep = QA.element(app, labelBeginsWith: "Better sleep")
        let energy = QA.element(app, labelBeginsWith: "More energy")
        let recovery = QA.element(app, labelBeginsWith: "Faster recovery")
        let next = QA.button(app, "Continue")

        QA.shot("state-goal-0")
        QA.write("continueEnabled=\(next.isEnabled)", to: "state-goal-0.txt")

        QA.tap(sleep, in: app)
        QA.pause(0.6)
        QA.shot("state-goal-1")
        XCTAssertTrue(sleep.isSelected, "first tap selects")

        QA.tap(energy, in: app)
        QA.pause(0.6)
        QA.shot("state-goal-2")
        XCTAssertTrue(sleep.isSelected && energy.isSelected, "second tap adds")

        QA.tap(recovery, in: app)
        QA.pause(0.6)
        QA.shot("state-goal-3rd-tap")
        XCTAssertFalse(sleep.isSelected, "third tap replaces the oldest")
        XCTAssertTrue(energy.isSelected && recovery.isSelected, "third tap keeps the newer and adds the new one")
        QA.write("afterThird sleep=\(sleep.isSelected) energy=\(energy.isSelected) recovery=\(recovery.isSelected) continueEnabled=\(next.isEnabled)", to: "state-goal-3rd-tap.txt")
    }

    func testHealthUnavailable() {
        let app = QA.launch(step: "health", goals: goals, extra: ["-useMockHealth", "-noctisHealthUnavailable"])
        QA.pause(2.5)
        QA.capturePages(app, "state-health-unavailable")
        XCTAssertTrue(QA.text(app, containing: "isn't available").exists, "unavailable banner shown")
        QA.tap(QA.button(app, "Continue without Health data"), in: app)
        XCTAssertTrue(QA.text(app, containing: "gently informed").waitForExistence(timeout: 5), "skip reaches Notifications")
    }

    /// Real HealthKit: decline in the system sheet, continue, and Plan must
    /// show the no-history branch.
    func testHealthDeniedThenPlanWithoutHistory() {
        XCUIApplication().resetAuthorizationStatus(for: .health)
        let app = QA.launch(step: "health", goals: goals)
        QA.pause(2)
        QA.tap(QA.button(app, "Connect Apple Health"), in: app)
        let dontAllow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Don'")).firstMatch
        // iOS 27's sheet only shows its Allow / Don't Allow buttons once
        // the category list has been scrolled to the end.
        if app.navigationBars["Health Access"].waitForExistence(timeout: 8) && !dontAllow.exists {
            for _ in 0..<4 where !dontAllow.exists {
                app.tables.firstMatch.swipeUp()
                QA.pause(0.5)
            }
        }
        if dontAllow.waitForExistence(timeout: 8) {
            QA.shot("state-health-sheet")
            dontAllow.tap()
            // iOS follows a decline with its own "Health Access" notice.
            let ok = app.buttons.matching(NSPredicate(format: "label == 'OK'")).firstMatch
            if ok.waitForExistence(timeout: 5) {
                QA.shot("state-health-declined-notice")
                ok.tap()
            }
        } else {
            QA.shot("state-health-sheet-MISSING")
            QA.write(app.debugDescription, to: "state-health-sheet-tree.txt")
            XCTFail("HealthKit permission sheet did not appear")
        }
        XCTAssertTrue(QA.text(app, containing: "gently informed").waitForExistence(timeout: 8), "decline proceeds to Notifications")
        QA.tap(QA.button(app, "Not now"), in: app)
        QA.pause(5)
        QA.capturePages(app, "state-plan-no-history")
        XCTAssertTrue(QA.text(app, containing: "tonight is your first night").exists, "no-history branch")
    }

    func testPlanWithHistory() {
        let app = QA.launch(step: "health", goals: goals, extra: ["-useMockHealth"])
        QA.pause(2)
        QA.tap(QA.button(app, "Connect Apple Health"), in: app)
        XCTAssertTrue(QA.text(app, containing: "gently informed").waitForExistence(timeout: 8))
        QA.tap(QA.button(app, "Not now"), in: app)
        QA.pause(5)
        QA.capturePages(app, "state-plan-history")
        // The count depends on the time of day (see the report), so check
        // the branch, not the number.
        let history = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*already have [0-9]+ nights.*")).firstMatch
        XCTAssertTrue(history.exists, "history branch shows the night count")
        QA.write(history.exists ? history.label : "missing", to: "state-plan-history.txt")
    }

    func testPlanError() {
        let fresh = QA.launch(step: "health", goals: goals, extra: ["-useMockHealth", "-noctisHealthQueryFails"])
        QA.pause(2)
        QA.tap(QA.button(fresh, "Connect Apple Health"), in: fresh)
        XCTAssertTrue(QA.text(fresh, containing: "gently informed").waitForExistence(timeout: 8))
        QA.tap(QA.button(fresh, "Not now"), in: fresh)
        let retry = QA.button(fresh, "Try again")
        XCTAssertTrue(retry.waitForExistence(timeout: 10), "failure state offers Try again")
        QA.pause(1)
        QA.capturePages(fresh, "state-plan-error")
        let continueAnyway = QA.button(fresh, "Continue anyway")
        XCTAssertTrue(continueAnyway.exists, "failure state offers Continue anyway")
        QA.tap(continueAnyway, in: fresh)
        XCTAssertTrue(QA.text(fresh, containing: "plan is ready").waitForExistence(timeout: 8), "Continue anyway reaches the plan")
        QA.pause(1.5)
        QA.shot("state-plan-error-continued")
    }

    /// Needs a fresh install (the system prompt only appears once).
    func testNotificationsGranted() {
        runNotifications(allow: true)
    }

    /// Needs a fresh install (the system prompt only appears once).
    func testNotificationsDenied() {
        runNotifications(allow: false)
    }

    private func runNotifications(allow: Bool) {
        let name = allow ? "state-notifications-granted" : "state-notifications-denied"
        let app = QA.launch(step: "notifications", goals: goals)
        QA.pause(2.5)
        QA.tap(QA.button(app, "Allow Notifications"), in: app)
        let alert = QA.springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 8) {
            QA.shot("\(name)-prompt")
            // The system label uses a typographic apostrophe ("Don’t Allow").
            let predicate = allow ? NSPredicate(format: "label == 'Allow'") : NSPredicate(format: "label BEGINSWITH 'Don'")
            alert.buttons.matching(predicate).firstMatch.tap()
        } else {
            QA.shot("\(name)-prompt-MISSING")
            XCTFail("notification prompt did not appear")
        }
        QA.pause(3)
        QA.capturePages(app, name)
        QA.inspect(app, name)
        if allow {
            XCTAssertTrue(QA.text(app, containing: "plan").waitForExistence(timeout: 8), "granting moves on to Plan")
        }
    }

    func testPaywallLoadingAndLoadedStates() {
        let app = QA.launch(step: "paywall", goals: goals)
        QA.shot("state-paywall-loading")
        QA.pause(6)
        QA.capturePages(app, "state-paywall-after-load")
        let loaded = QA.text(app, containing: "per year").exists || QA.element(app, labelBeginsWith: "Yearly").exists
        QA.write("loaded=\(loaded) tryAgain=\(QA.button(app, "Try again").exists)", to: "state-paywall.txt")
        QA.inspect(app, "state-paywall-after-load")
    }

    // MARK: - Flow

    /// Back keeps answers on every step.
    func testBackKeepsAnswers() {
        let app = QA.launch()
        QA.pause(2)
        QA.tap(QA.button(app, "Begin"), in: app)
        XCTAssertTrue(QA.text(app, containing: "most to you").waitForExistence(timeout: 5))
        QA.tap(QA.element(app, labelBeginsWith: "Steady routine"), in: app)
        QA.tap(QA.element(app, labelBeginsWith: "Clearer focus"), in: app)
        QA.tap(QA.button(app, "Continue"), in: app)

        XCTAssertTrue(QA.text(app, containing: "rhythm").waitForExistence(timeout: 5))
        let wake = QA.element(app, labelBeginsWith: "Wake time")
        let need = QA.element(app, labelBeginsWith: "Sleep need")
        let wakeBefore = wake.value as? String ?? "?"
        adjust(wake, in: app, up: true)
        adjust(need, in: app, up: false)
        let wakeSet = wake.value as? String ?? "?"
        let needSet = need.value as? String ?? "?"
        var log = "wake \(wakeBefore) -> \(wakeSet); need -> \(needSet)\n"
        log += "wake type=\(wake.elementType == .slider ? "slider" : "\(wake.elementType.rawValue)") need type=\(need.elementType == .slider ? "slider" : "\(need.elementType.rawValue)")\n"
        XCTAssertNotEqual(wakeBefore, wakeSet, "wake ruler adjustable")
        QA.tap(QA.button(app, "Continue"), in: app)

        XCTAssertTrue(QA.text(app, containing: "mornings").waitForExistence(timeout: 5))
        // VoiceOver adjusts the ring through its slider representation;
        // XCTest can't send VoiceOver's increment on iOS 26, so check the
        // exposure: an adjustable slider whose value names a segment.
        let ring = QA.element(app, labelBeginsWith: "Sample night")
        let ringValue = ring.value as? String ?? "?"
        log += "ring type=\(ring.elementType == .slider ? "slider" : "\(ring.elementType.rawValue)") value=\(ringValue)\n"
        XCTAssertEqual(ring.elementType, .slider, "sample ring is adjustable")
        XCTAssertNotNil(ringValue.range(of: #"^(Deep|Core|REM|Awake), \d+h \d{2}m$"#, options: .regularExpression), "ring value names a segment")

        QA.tap(QA.button(app, "Back"), in: app)
        XCTAssertTrue(QA.text(app, containing: "rhythm").waitForExistence(timeout: 5))
        XCTAssertEqual(QA.element(app, labelBeginsWith: "Wake time").value as? String, wakeSet, "Back keeps wake")
        XCTAssertEqual(QA.element(app, labelBeginsWith: "Sleep need").value as? String, needSet, "Back keeps need")

        QA.tap(QA.button(app, "Back"), in: app)
        XCTAssertTrue(QA.text(app, containing: "most to you").waitForExistence(timeout: 5))
        XCTAssertTrue(QA.element(app, labelBeginsWith: "Steady routine").isSelected, "Back keeps goal 1")
        XCTAssertTrue(QA.element(app, labelBeginsWith: "Clearer focus").isSelected, "Back keeps goal 2")

        // Forward again through every step, stepping back once at each.
        QA.tap(QA.button(app, "Continue"), in: app)
        QA.tap(QA.button(app, "Continue"), in: app)
        XCTAssertTrue(QA.text(app, containing: "mornings").waitForExistence(timeout: 5))
        QA.tap(QA.button(app, "Continue"), in: app)
        XCTAssertTrue(QA.text(app, containing: "signals").waitForExistence(timeout: 5))
        QA.tap(QA.button(app, "Back"), in: app)
        XCTAssertTrue(QA.text(app, containing: "mornings").waitForExistence(timeout: 5), "Back from Health")
        QA.tap(QA.button(app, "Continue"), in: app)
        QA.tap(QA.button(app, "Continue without Health data"), in: app)
        XCTAssertTrue(QA.text(app, containing: "gently informed").waitForExistence(timeout: 5))
        QA.tap(QA.button(app, "Back"), in: app)
        XCTAssertTrue(QA.text(app, containing: "signals").waitForExistence(timeout: 5), "Back from Notifications")
        QA.tap(QA.button(app, "Continue without Health data"), in: app)
        QA.tap(QA.button(app, "Not now"), in: app)
        XCTAssertTrue(QA.text(app, containing: "plan is ready").waitForExistence(timeout: 10))
        QA.pause(1)
        let chipsOK = QA.text(app, containing: "Steady routine").exists && QA.text(app, containing: "Clearer focus").exists
        XCTAssertTrue(chipsOK, "Plan shows the chosen goals")
        log += "plan wake shown: \(wakeSet) present=\(QA.text(app, containing: String(wakeSet.prefix(4))).exists)\n"
        QA.shot("flow-back-plan")
        QA.tap(QA.button(app, "Back"), in: app)
        XCTAssertTrue(QA.text(app, containing: "gently informed").waitForExistence(timeout: 5), "Back from Plan")
        QA.write(log, to: "flow-back.txt")
    }

    /// Force-quit on each step and relaunch: resumes on that step with the
    /// answers intact.
    func testForceQuitResumesEveryStep() {
        var app = QA.launch()
        var log = ""
        func relaunch() {
            app.terminate()
            app = QA.launch(reset: false)
            QA.pause(2)
        }
        func check(_ fragment: String, _ step: String) {
            let onStep = QA.text(app, containing: fragment).waitForExistence(timeout: 6)
            log += "\(step): resumed=\(onStep)\n"
            XCTAssertTrue(onStep, "resume on \(step)")
        }
        QA.pause(2)
        QA.tap(QA.button(app, "Begin"), in: app)
        check("most to you", "goal")
        QA.tap(QA.element(app, labelBeginsWith: "More energy"), in: app)
        QA.tap(QA.element(app, labelBeginsWith: "Clearer focus"), in: app)
        relaunch()
        check("most to you", "goal (after selecting)")
        let kept = QA.element(app, labelBeginsWith: "More energy").isSelected && QA.element(app, labelBeginsWith: "Clearer focus").isSelected
        log += "goal selections kept=\(kept)\n"
        XCTAssertTrue(kept, "goal selections survive force-quit")

        QA.tap(QA.button(app, "Continue"), in: app)
        check("rhythm", "rhythm")
        let wake = QA.element(app, labelBeginsWith: "Wake time")
        adjust(wake, in: app, up: true)
        adjust(wake, in: app, up: true)
        let wakeSet = wake.value as? String ?? "?"
        relaunch()
        check("rhythm", "rhythm (after adjusting)")
        let wakeAfter = QA.element(app, labelBeginsWith: "Wake time").value as? String ?? "?"
        log += "wake set=\(wakeSet) after=\(wakeAfter)\n"
        XCTAssertEqual(wakeSet, wakeAfter, "wake survives force-quit")

        QA.tap(QA.button(app, "Continue"), in: app)
        check("mornings", "sample")
        relaunch()
        check("mornings", "sample")

        QA.tap(QA.button(app, "Continue"), in: app)
        check("signals", "health")
        relaunch()
        check("signals", "health")

        QA.tap(QA.button(app, "Continue without Health data"), in: app)
        check("gently informed", "notifications")
        relaunch()
        check("gently informed", "notifications")

        QA.tap(QA.button(app, "Not now"), in: app)
        check("plan is ready", "plan")
        relaunch()
        check("plan", "plan")
        QA.pause(4)
        let planKept = QA.text(app, containing: "More energy").exists && QA.text(app, containing: "Clearer focus").exists
        log += "plan goals kept=\(planKept)\n"
        XCTAssertTrue(planKept, "plan keeps goals after force-quit")
        QA.shot("flow-forcequit-plan")

        QA.tap(QA.button(app, "Continue"), in: app)
        check("deeper", "paywall")
        relaunch()
        check("deeper", "paywall")
        QA.write(log, to: "flow-forcequit.txt")
    }

    /// Every skip path reaches the next step, and a finished onboarding
    /// relaunches straight into the app.
    func testSkipPathsAndFinish() {
        var log = ""
        var app = QA.launch(step: "goal")
        QA.pause(1.5)
        QA.tap(QA.button(app, "Skip for now"), in: app)
        log += "goal skip -> rhythm: \(QA.text(app, containing: "rhythm").waitForExistence(timeout: 5))\n"
        app.terminate()

        app = QA.launch(step: "health", goals: goals)
        QA.pause(1.5)
        QA.tap(QA.button(app, "Continue without Health data"), in: app)
        log += "health skip -> notifications: \(QA.text(app, containing: "gently informed").waitForExistence(timeout: 5))\n"
        QA.tap(QA.button(app, "Not now"), in: app)
        log += "notifications skip -> plan: \(QA.text(app, containing: "plan").waitForExistence(timeout: 5))\n"
        app.terminate()

        app = QA.launch(step: "paywall", goals: goals)
        QA.pause(3)
        QA.tap(QA.button(app, "Close"), in: app)
        let viaClose = app.tabBars.firstMatch.waitForExistence(timeout: 8)
        log += "paywall close -> app: \(viaClose)\n"
        QA.shot("flow-app-after-close")
        app.terminate()

        app = QA.launch(step: "paywall", goals: goals)
        QA.pause(3)
        QA.tap(QA.button(app, "Continue with limited version"), in: app)
        let viaLimited = app.tabBars.firstMatch.waitForExistence(timeout: 8)
        log += "paywall limited -> app: \(viaLimited)\n"
        app.terminate()

        app = QA.launch(reset: false)
        QA.pause(3)
        let straightToApp = app.tabBars.firstMatch.waitForExistence(timeout: 8) && !QA.button(app, "Begin").exists
        log += "relaunch after finishing -> app: \(straightToApp)\n"
        QA.shot("flow-relaunch-after-finish")
        XCTAssertTrue(viaClose && viaLimited && straightToApp)
        QA.write(log, to: "flow-skip.txt")
    }

    // MARK: - Helpers

    /// A horizontal drag across the control. (XCTest's slider adjust can't
    /// drive these: their accessibility value is text like "7:00 AM".)
    private func adjust(_ element: XCUIElement, in app: XCUIApplication, up: Bool) {
        guard element.waitForExistence(timeout: 5) else { return }
        let from = element.coordinate(withNormalizedOffset: CGVector(dx: up ? 0.6 : 0.4, dy: 0.5))
        let to = element.coordinate(withNormalizedOffset: CGVector(dx: up ? 0.4 : 0.6, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        QA.pause(0.8)
    }
}
