import XCTest

/// QA part 3, step 6: the app makes no network request of its own. A DEBUG recorder (`RequestRecorder`, registered with `-noctisDebugProbe`) counts every
/// request through URLSession's shared and default sessions; this walks the five tabs, Coach with a question, the profile, Settings, Privacy and Reviews, and
/// asserts the count is still zero. Not covered, and held by other checks: StoreKit's own traffic (the system's), a session with a custom URLProtocol list
/// (the symbol audit finds no URLSession in the app binary at all), and anything outside the app's process.
@MainActor
final class NoRequestsQATests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func requests(_ app: XCUIApplication) -> Int {
        let probe = app.descendants(matching: .any)["debug.probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10), "the probe is on Home")
        return probe.label.split(separator: ";").first { $0.hasPrefix("requests=") }.flatMap { Int($0.dropFirst("requests=".count)) } ?? -1
    }

    func testTheAppMakesNoRequestsAcrossTheTabsAndTheScreensBehindThem() {
        let app = QA.launch(extra: ["-useMockHealth", "-mockScenario", "full", "-noctisSkipOnboarding", "-noctisDebugProbe", "-forceTier", "premium"])
        XCTAssertEqual(requests(app), 0, "at launch")
        for tab in ["Sleep", "Recovery", "Insights", "Coach", "Home"] {
            let button = app.tabBars.buttons[tab]
            if button.waitForExistence(timeout: 5) { button.tap() }
            QA.pause(1.2)
        }
        XCTAssertEqual(requests(app), 0, "after every tab")
        // Coach answers a question on the device.
        app.tabBars.buttons["Coach"].tap()
        let question = app.descendants(matching: .any)["coach.question.recovery.lower"]
        if question.waitForExistence(timeout: 6) { question.tap(); QA.pause(4) }
        app.tabBars.buttons["Home"].tap()
        QA.pause(1)
        // The profile, Settings and the Privacy Center.
        let avatar = app.buttons.matching(identifier: "home.profile").firstMatch
        if avatar.waitForExistence(timeout: 5) { avatar.tap(); QA.pause(1.5) }
        for label in ["Settings", "Privacy", "Data management"] {
            let row = QA.button(app, label)
            if row.waitForExistence(timeout: 3) { row.tap(); QA.pause(1.2); if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() } }
        }
        while !app.tabBars.buttons["Home"].isHittable, app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap(); QA.pause(0.6) }
        app.tabBars.buttons["Home"].tap()
        XCTAssertEqual(requests(app), 0, "after the profile, Settings, Privacy and Data management")
    }
}
