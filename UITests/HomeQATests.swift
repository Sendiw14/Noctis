import XCTest

/// Home QA (APP_RULES.md R11): the full state scrolled page by page,
/// Recovery detail with its calculation open, and frames of the zoom
/// transition in both directions. Screenshots land in `QA_OUT`.
@MainActor
final class HomeQATests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Home in a pinned mode, so results don't depend on the time of day.
    private func launchHome(_ scenario: String = "full", mode: String = "day", extra: [String] = []) -> XCUIApplication {
        QA.launch(extra: ["-useMockHealth", "-mockScenario", scenario, "-noctisSkipOnboarding", "-homeMode", mode] + extra)
    }

    private func recoveryCard(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recovery '")).firstMatch
    }

    func testFullStatePages() {
        let app = launchHome()
        XCTAssertTrue(recoveryCard(app).waitForExistence(timeout: 10))
        QA.pause(2)
        QA.capturePages(app, "home-full")
        QA.inspect(app, "home-full")
    }

    func testEveningFullStatePages() {
        let app = launchHome(mode: "evening")
        XCTAssertTrue(recoveryCard(app).waitForExistence(timeout: 10))
        QA.pause(2)
        QA.capturePages(app, "home-evening-full")
        QA.inspect(app, "home-evening-full")
    }

    func testFactorCapsuleOpensDetailAtThatFactor() {
        let app = launchHome()
        let capsule = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Consistency '")).firstMatch
        XCTAssertTrue(capsule.waitForExistence(timeout: 10))
        QA.pause(1)
        capsule.tap()
        XCTAssertTrue(app.navigationBars["Recovery"].waitForExistence(timeout: 5))
        QA.pause(1)
        QA.shot("recovery-detail-focus-consistency")
        // The detail row (one element, its value in words) scrolled into view.
        let row = QA.element(app, labelBeginsWith: "Consistency ")
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(row.isHittable)
    }

    func testRecoveryDetailZoom() {
        let app = launchHome()
        let card = recoveryCard(app)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        QA.pause(2)

        // XCTest waits out animations after a tap, so the transition is
        // captured from a screen recording; these mark when each tap began.
        QA.write("\(Date().timeIntervalSince1970)", to: "zoom-open-time.txt")
        card.tap()
        let calculation = app.buttons["How this is calculated"]
        XCTAssertTrue(calculation.waitForExistence(timeout: 5))
        QA.pause(1)
        QA.shot("recovery-detail")
        QA.tap(calculation, in: app)
        QA.pause(1)
        QA.capturePages(app, "recovery-detail-calculation")
        QA.inspect(app, "recovery-detail")

        QA.write("\(Date().timeIntervalSince1970)", to: "zoom-close-time.txt")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(recoveryCard(app).waitForExistence(timeout: 5))
    }

    func testCardsOpenTheirDestinations() {
        let app = launchHome()
        XCTAssertTrue(recoveryCard(app).waitForExistence(timeout: 10))

        QA.tap(app.buttons["Profile"], in: app)
        XCTAssertTrue(QA.text(app, containing: "Coming soon").waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        let lastNight = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Last night'")).firstMatch
        QA.tap(lastNight, in: app)
        // The tab bar minimizes once Home scrolls, so read the Sleep tab's
        // placeholder rather than the bar.
        XCTAssertTrue(QA.text(app, containing: "Coming soon").waitForExistence(timeout: 3))
    }
}
