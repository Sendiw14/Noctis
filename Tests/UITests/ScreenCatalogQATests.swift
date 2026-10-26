import XCTest

/// Every Home, Sleep and Recovery screen on every mock scenario, paged through
/// top to bottom, for the screenshot catalog (`Screenshots/`). Nothing here
/// asserts: a screen that can't be reached is skipped and the run goes on, so
/// one missing element never hides the rest. Shots are named
/// `cat-<tab>-<variant>-<scenario>-p<page>`.
@MainActor
final class ScreenCatalogQATests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private static let scenarios = [
        "full", "sleepOnly", "learning", "empty", "stale", "gap",
        "messyNight", "lateBedtime", "steady", "recoveryDip",
    ]

    // MARK: - Plumbing

    private func launch(_ scenario: String, route: String? = nil, mode: String = "day", extra: [String] = []) -> XCUIApplication {
        var arguments = ["-useMockHealth", "-mockScenario", scenario, "-noctisSkipOnboarding", "-homeMode", mode]
        if let route { arguments += ["-noctisInitialRoute", route] }
        return QA.launch(extra: arguments + extra)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// The skeleton is gone and the day's reveal has finished.
    private func settle() {
        QA.pause(4.5)
    }

    private func page(_ name: String, route: String? = nil, scenario: String, mode: String = "day", extra: [String] = [], maxPages: Int) {
        let app = launch(scenario, route: route, mode: mode, extra: extra)
        settle()
        QA.capturePages(app, name, maxPages: maxPages)
        app.terminate()
    }

    /// The states that aren't a mock scenario: no access, a failed read, no
    /// Health on the device, and the first snapshot still loading.
    private func systemStates(_ tab: String, route: String?, mode: String = "day", maxPages: Int = 2) {
        page("cat-\(tab)-\(mode)-unauthorized", route: route, scenario: "full", mode: mode, extra: ["-mockUnauthorized"], maxPages: maxPages)
        page("cat-\(tab)-\(mode)-error", route: route, scenario: "full", mode: mode, extra: ["-noctisHealthQueryFails"], maxPages: maxPages)
        page("cat-\(tab)-\(mode)-healthUnavailable", route: route, scenario: "full", mode: mode, extra: ["-noctisHealthUnavailable"], maxPages: maxPages)
        let app = launch("full", route: route, mode: mode, extra: ["-mockLatency", "20"])
        QA.pause(1.5)
        QA.shot("cat-\(tab)-\(mode)-skeleton-p0")
        app.terminate()
    }

    /// Scrolls until `target` is on screen, in a few bounded swipes.
    private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<8 where !target.isHittable {
            scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
                .press(
                    forDuration: 0.05, thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.35)), withVelocity: .slow,
                    thenHoldForDuration: 0.3)
            QA.pause(0.4)
        }
        QA.pause(0.8)
    }

    private func scrollToTop(_ app: XCUIApplication, until target: XCUIElement) {
        for _ in 0..<6 where !target.isHittable {
            app.swipeDown()
            QA.pause(0.4)
        }
        QA.pause(0.6)
    }

    // MARK: - Home

    func testHomeDay() {
        for scenario in Self.scenarios {
            page("cat-home-day-\(scenario)", scenario: scenario, mode: "day", maxPages: 6)
        }
    }

    func testHomeEvening() {
        for scenario in Self.scenarios {
            page("cat-home-evening-\(scenario)", scenario: scenario, mode: "evening", maxPages: 6)
        }
    }

    func testHomeSystemStates() {
        systemStates("home", route: nil, mode: "day", maxPages: 3)
        systemStates("home", route: nil, mode: "evening", maxPages: 3)
    }

    func testOtherTabsAndProfile() {
        let app = launch("full")
        settle()
        for tab in ["Insights", "Coach"] {
            let button = app.tabBars.buttons[tab]
            if button.waitForExistence(timeout: 5) {
                button.tap()
                QA.pause(1.5)
                QA.shot("cat-tab-\(tab.lowercased())-p0")
            }
        }
        let home = app.tabBars.buttons["Home"]
        if home.waitForExistence(timeout: 5) {
            home.tap()
            QA.pause(1.5)
        }
        let profile = app.buttons["Profile"]
        if profile.waitForExistence(timeout: 5) {
            profile.tap()
            QA.pause(1.5)
            QA.shot("cat-home-profile-p0")
        }
        app.terminate()
    }

    // MARK: - Sleep

    func testSleep() {
        for scenario in Self.scenarios {
            for (range, route, pages) in [("day", "sleep", 6), ("week", "sleep:week", 5), ("month", "sleep:month", 5)] {
                page("cat-sleep-\(range)-\(scenario)", route: route, scenario: scenario, maxPages: pages)
            }
        }
    }

    func testSleepSystemStates() {
        systemStates("sleep", route: "sleep")
    }

    // MARK: - Recovery

    func testRecovery() {
        for scenario in Self.scenarios {
            for (range, route, pages) in [("today", "recovery", 6), ("7d", "recovery:7d", 5), ("30d", "recovery:30d", 5), ("90d", "recovery:90d", 5)] {
                page("cat-recovery-\(range)-\(scenario)", route: route, scenario: scenario, maxPages: pages)
            }
        }
    }

    /// The three history ranges while the baseline forms (they say the same
    /// nights Today does).
    func testRecoveryLearningHistory() {
        for (range, route) in [("7d", "recovery:7d"), ("30d", "recovery:30d"), ("90d", "recovery:90d")] {
            page("cat-recovery-\(range)-learning", route: route, scenario: "learning", maxPages: 3)
        }
    }

    func testRecoverySystemStates() {
        systemStates("recovery", route: "recovery")
    }

    /// Each factor's page on its three ranges, and "How this is calculated".
    func testRecoveryFactorPages() {
        for scenario in ["full", "recoveryDip", "sleepOnly"] {
            let app = launch(scenario, route: "recovery")
            settle()
            for kind in ["sleepDuration", "hrv", "restingHeartRate", "sleepConsistency"] {
                let card = element(app, "recovery.factor.\(kind)")
                reveal(card, in: app)
                guard card.exists, card.isHittable else { continue }
                card.tap()
                guard element(app, "recovery.factorScreen").waitForExistence(timeout: 5) else { continue }
                QA.pause(1.5)
                let ranges = app.segmentedControls["recovery.factorRange"]
                for (name, token) in [("14 nights", "14"), ("30 nights", "30"), ("90 nights", "90")] {
                    scrollToTop(app, until: ranges)
                    if ranges.buttons[name].exists {
                        ranges.buttons[name].tap()
                        QA.pause(1.6)
                    }
                    QA.capturePages(app, "cat-recovery-factor-\(kind)-\(token)-\(scenario)", maxPages: 4)
                }
                app.navigationBars.buttons.firstMatch.tap()
                QA.pause(1)
            }
            let calculation = app.buttons["How this is calculated"]
            reveal(calculation, in: app)
            if calculation.exists, calculation.isHittable {
                calculation.tap()
                QA.pause(1.5)
                QA.capturePages(app, "cat-recovery-calculation-\(scenario)", maxPages: 6)
            }
            app.terminate()
        }
    }
}
