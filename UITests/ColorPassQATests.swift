import XCTest

/// The color and delight pass (APP_RULES.md R26), fast: iPhone 17 Pro, light
/// and dark. Each screen is captured at its top, then again with the field
/// scrolled away, so the status bar over the moving content is seen too.
@MainActor
final class ColorPassQATests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ scenario: String = "full", route: String? = nil, mode: String = "day") -> XCUIApplication {
        var arguments = ["-useMockHealth", "-mockScenario", scenario, "-noctisSkipOnboarding", "-homeMode", mode]
        if let route { arguments += ["-noctisInitialRoute", route] }
        return QA.launch(extra: arguments)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// One drag up over the side margin, the way the catalog scrolls.
    private func scroll(_ app: XCUIApplication, by fraction: CGFloat = 0.42) {
        let scrollView = app.scrollViews.firstMatch
        guard scrollView.exists else { return }
        scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8))
            .press(forDuration: 0.05, thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8 - fraction)), withVelocity: .slow, thenHoldForDuration: 0.4)
        QA.pause(0.7)
    }

    private func capture(_ name: String, route: String?, scenario: String = "full", mode: String = "day", scrolls: [CGFloat] = [0.42]) {
        let app = launch(scenario, route: route, mode: mode)
        QA.pause(5)
        QA.shot("\(name)-top")
        for (index, amount) in scrolls.enumerated() {
            scroll(app, by: amount)
            QA.shot("\(name)-scrolled\(index + 1)")
        }
        app.terminate()
    }

    func testHome() {
        capture("cp-home-day", route: nil, scrolls: [0.5, 0.5])
        capture("cp-home-evening", route: nil, mode: "evening", scrolls: [0.5, 0.5])
    }

    func testSleep() {
        capture("cp-sleep-day", route: "sleep", scrolls: [0.42, 0.5])
        capture("cp-sleep-week", route: "sleep:week", scrolls: [0.42])
        capture("cp-sleep-month", route: "sleep:month", scrolls: [0.42])
        capture("cp-sleep-highs", route: "sleep", scenario: "highs", scrolls: [0.42])
        capture("cp-sleep-messy", route: "sleep", scenario: "messyNight", scrolls: [0.42])
        capture("cp-sleep-sleeponly", route: "sleep", scenario: "sleepOnly", scrolls: [0.42])
        capture("cp-sleep-learning", route: "sleep", scenario: "learning", scrolls: [])
        capture("cp-sleep-empty", route: "sleep", scenario: "empty", scrolls: [])
    }

    func testRecovery() {
        capture("cp-rec-today", route: "recovery", scrolls: [0.42, 0.5])
        capture("cp-rec-7d", route: "recovery:7d", scrolls: [0.42])
        capture("cp-rec-30d", route: "recovery:30d", scrolls: [0.42])
        capture("cp-rec-90d", route: "recovery:90d", scrolls: [0.42])
        capture("cp-rec-highs", route: "recovery", scenario: "highs", scrolls: [])
        capture("cp-rec-learning", route: "recovery", scenario: "learning", scrolls: [])
        capture("cp-rec-empty", route: "recovery", scenario: "empty", scrolls: [])
    }

    /// The states that keep their color field: no data, learning, a failed read and no access.
    func testStates() {
        for tab in [("sleep", "sleep"), ("rec", "recovery")] {
            capture("cp-\(tab.0)-empty2", route: tab.1, scenario: "empty", scrolls: [])
            capture("cp-\(tab.0)-learning2", route: tab.1, scenario: "learning", scrolls: [])
            let app = QA.launch(extra: ["-useMockHealth", "-mockScenario", "full", "-noctisSkipOnboarding", "-homeMode", "day", "-noctisInitialRoute", tab.1, "-noctisHealthQueryFails"])
            QA.pause(5)
            QA.shot("cp-\(tab.0)-error")
            app.terminate()
            let denied = QA.launch(extra: ["-useMockHealth", "-mockScenario", "full", "-noctisSkipOnboarding", "-homeMode", "day", "-noctisInitialRoute", tab.1, "-mockUnauthorized"])
            QA.pause(5)
            QA.shot("cp-\(tab.0)-unauthorized")
            denied.terminate()
        }
    }

    /// The four factor pages, each in its own color.
    func testFactorDetail() {
        for kind in ["sleepDuration", "hrv", "restingHeartRate", "sleepConsistency"] {
            let app = launch("full", route: "recovery")
            QA.pause(4.5)
            let card = element(app, "recovery.factor.\(kind)")
            for _ in 0..<8 where !card.isHittable {
                scroll(app, by: 0.5)
            }
            QA.pause(0.6)
            guard card.exists, card.isHittable else { app.terminate(); continue }
            card.tap()
            if element(app, "recovery.factorScreen").waitForExistence(timeout: 6) {
                QA.pause(1.4)
                QA.shot("cp-factor-\(kind)-top")
                scroll(app, by: 0.5)
                QA.shot("cp-factor-\(kind)-scrolled1")
            }
            app.terminate()
        }
    }

    /// Home's Recovery ring zooms into a pushed Recovery on Today: the field
    /// sits below the navigation bar there.
    func testPushedRecovery() {
        let app = launch("full", route: nil)
        QA.pause(4.5)
        let hero = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.hero'")).firstMatch
        if hero.waitForExistence(timeout: 8) {
            hero.tap()
            QA.pause(2)
            QA.shot("cp-pushed-recovery-top")
            scroll(app, by: 0.42)
            QA.shot("cp-pushed-recovery-scrolled1")
        }
        app.terminate()
    }
}
