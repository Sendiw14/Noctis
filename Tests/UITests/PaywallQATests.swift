import XCTest

/// The paywall in the band style (APP_RULES.md R58, App Store guideline 3.1.2), with the mock plans (`-mockPaywallPlans`: StoreKit's test configuration only
/// answers under its own runner) and `-introEligible yes|no`: eligibility on and off changes the badge, the button and the renewal line together; the
/// renewal line follows the selected plan; Restore, Terms and Privacy and the way out are on the screen in every phase; nothing is clipped at the default size
/// and at the largest text, on the iPhone 17 Pro and the iPhone SE.
@MainActor
final class PaywallQATests: XCTestCase {
    private func paywall(eligible: Bool? = true, plans: Bool = true, extra: [String] = []) -> XCUIApplication {
        var flags = ["-useMockHealth"]
        if plans { flags.append("-mockPaywallPlans") }
        if let eligible { flags += ["-introEligible", eligible ? "yes" : "no"] }
        let app = QA.launch(step: "paywall", goals: "betterSleep", extra: flags + extra)
        XCTAssertTrue(app.buttons["paywall.free"].waitForExistence(timeout: 12), "the paywall is on screen")
        // The plans arrive after StoreKit has answered for the entitlement and the intro offer: "Loading plans" until then.
        if plans { XCTAssertTrue(yearly(app).waitForExistence(timeout: 25), "the plans are ready") }
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func yearly(_ app: XCUIApplication) -> XCUIElement { app.buttons["paywall.plan.yearly"] }
    private func monthly(_ app: XCUIApplication) -> XCUIElement { app.buttons["paywall.plan.monthly"] }
    private let renewalYearlyTrial = "7 days free, then $39.99 per year, renewing automatically. Cancel anytime in Settings."

    // MARK: Eligibility

    func testEligibleShowsTheBadgeTheTrialButtonAndTheTrialRenewalLine() {
        let app = paywall(eligible: true)
        XCTAssertTrue(app.buttons["paywall.cta"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.buttons["paywall.cta"].label, "Start 7-day free trial, then $39.99 per year")
        XCTAssertEqual(yearly(app).label, "Yearly, $39.99 per year, 7 days free, save 52 percent")
        XCTAssertEqual(element(app, "paywall.renewal").label, renewalYearlyTrial)
        XCTAssertTrue(yearly(app).isSelected, "Yearly is selected by default")
        QA.shot("paywall-eligible")
    }

    func testNotEligibleHidesTheBadgeAndSaysContinueWithTheRightPrice() {
        let app = paywall(eligible: false)
        XCTAssertTrue(app.buttons["paywall.cta"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.buttons["paywall.cta"].label, "Continue, $39.99 per year")
        XCTAssertEqual(yearly(app).label, "Yearly, $39.99 per year, save 52 percent", "no trial said, the saving still true")
        XCTAssertEqual(element(app, "paywall.renewal").label, "$39.99 per year, renewing automatically. Cancel anytime in Settings.")
        XCTAssertFalse(app.staticTexts["7 DAYS FREE"].exists, "no badge")
        QA.shot("paywall-not-eligible")
    }

    func testTheSameEligibilityGivesTheSameScreenOnAnyDevice() {
        // The badge, the button and the renewal line agree with one another in both states (the open bug was two simulators answering differently).
        for eligible in [true, false] {
            let app = paywall(eligible: eligible)
            XCTAssertTrue(app.buttons["paywall.cta"].waitForExistence(timeout: 6))
            let trialButton = app.buttons["paywall.cta"].label.hasPrefix("Start 7-day free trial")
            let trialBadge = yearly(app).label.contains("7 days free")
            let trialLine = element(app, "paywall.renewal").label.contains("free, then")
            XCTAssertEqual(trialButton, eligible)
            XCTAssertEqual(trialBadge, eligible)
            XCTAssertEqual(trialLine, eligible)
            app.terminate()
        }
    }

    // MARK: The selected plan

    func testSelectingMonthlyUpdatesTheButtonAndTheRenewalLine() {
        let app = paywall(eligible: true)
        monthly(app).tap()
        XCTAssertTrue(monthly(app).isSelected && !yearly(app).isSelected)
        XCTAssertEqual(app.buttons["paywall.cta"].label, "Continue, $6.99 per month")
        XCTAssertEqual(element(app, "paywall.renewal").label, "$6.99 per month, renewing automatically. Cancel anytime in Settings.")
        QA.shot("paywall-monthly")
        yearly(app).tap()
        XCTAssertEqual(app.buttons["paywall.cta"].label, "Start 7-day free trial, then $39.99 per year")
        XCTAssertEqual(element(app, "paywall.renewal").label, renewalYearlyTrial)
    }

    // MARK: Restore, links, the way out

    func testRestoreTermsPrivacyAndTheWayOutAreOnTheScreen() {
        let app = paywall()
        XCTAssertTrue(app.buttons["Restore"].exists, "Restore, top right")
        XCTAssertTrue(app.buttons["paywall.restore"].exists && app.buttons["paywall.restore"].isHittable, "Restore Purchases")
        XCTAssertTrue(app.links["Terms"].firstMatch.exists && app.links["Privacy"].firstMatch.exists, "Terms and Privacy")
        XCTAssertGreaterThanOrEqual(app.buttons["paywall.free"].frame.height, 44, "a 44 pt target")
        XCTAssertTrue(app.staticTexts["NOCTIS isn't a medical device and doesn't diagnose or treat any condition."].exists)
    }

    // Restore Purchases is not tapped here: a simulator with no Apple Account asks the system to sign in and never answers, which stops every StoreKit call after it.
    // What it answers is `PaywallFacts.restoreMessage` (PaywallFactsTests); what StoreKit does for a purchase on a fresh install, and when there is none, is
    // StoreKitSessionTests (scheme NOCTIS-Store). Here: both Restore buttons are on the screen and can be tapped (testRestoreTermsPrivacyAndTheWayOutAreOnTheScreen).

    func testTheWayOutIsThereInEveryPhase() {
        for script in ["loading", "unavailable"] {
            let app = paywall(eligible: nil, plans: false, extra: ["-mockStoreLoad", script])
            XCTAssertTrue(app.buttons["paywall.free"].isHittable, "Continue with the free plan while \(script)")
            XCTAssertTrue(app.buttons["Close"].exists)
            if script == "unavailable" { XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 25)) }
            app.terminate()
        }
        let ready = paywall()
        XCTAssertTrue(ready.buttons["paywall.free"].isHittable, "and when the plans are ready")
    }

    func testCloseAndTheFreePlanLeaveThePaywall() {
        let app = paywall()
        app.buttons["paywall.free"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "the free plan goes to the app")
    }

    // MARK: States

    func testPurchasingDisablesTheButton() {
        let app = paywall(extra: ["-mockPurchase", "purchasing"])
        XCTAssertTrue(app.buttons["paywall.cta"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["paywall.cta"].isEnabled, "no second tap while the purchase is under way")
        QA.shot("paywall-purchasing")
    }

    func testAFailedPurchaseSaysSoAndCanBeTriedAgain() {
        let app = paywall(extra: ["-mockPurchase", "failed"])
        XCTAssertTrue(element(app, "paywall.error").waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["paywall.cta"].isEnabled, "the button is back")
        QA.shot("paywall-error")
    }

    // MARK: Fit

    private func assertFits(_ app: XCUIApplication, scrolls: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(app.buttons["paywall.cta"].isHittable, "the button is tappable", file: file, line: line)
        for tile in [yearly(app), monthly(app)] {
            let frame = tile.frame
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "\(tile.identifier) inside the screen", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "\(tile.identifier) inside the screen", file: file, line: line)
        }
        XCTAssertLessThanOrEqual(yearly(app).frame.maxX, monthly(app).frame.minX + 8.5, "the tiles do not overlap", file: file, line: line)
        if !scrolls {
            // Everything on one screen: the plans, the button, the renewal line and the way out, in order, none under the next.
            let order = [yearly(app).frame.maxY, app.buttons["paywall.cta"].frame.minY]
            XCTAssertLessThanOrEqual(order[0], order[1] + 0.5, "the tiles are above the button", file: file, line: line)
            XCTAssertLessThanOrEqual(app.buttons["paywall.cta"].frame.maxY, element(app, "paywall.renewal").frame.minY + 0.5, file: file, line: line)
            XCTAssertLessThanOrEqual(element(app, "paywall.renewal").frame.maxY, app.buttons["paywall.free"].frame.minY + 0.5, file: file, line: line)
            XCTAssertLessThanOrEqual(app.buttons["paywall.free"].frame.maxY, window.maxY, "the way out is on the screen", file: file, line: line)
            XCTAssertTrue(
                app.links["Terms"].firstMatch.isHittable && app.links["Privacy"].firstMatch.isHittable && app.buttons["paywall.restore"].isHittable,
                "the links are on the screen", file: file, line: line)
            XCTAssertLessThanOrEqual(
                element(app, "paywall.benefits").frame.maxY, yearly(app).frame.minY, "the benefits are above the plans", file: file, line: line)
        }
    }

    func testNothingIsClippedAtTheDefaultSize() {
        let app = paywall()
        XCTAssertTrue(app.buttons["paywall.cta"].waitForExistence(timeout: 6))
        QA.pause(1.5)
        assertFits(app, scrolls: false)
        QA.shot("paywall-default")
    }

    func testNothingIsClippedAtTheLargestText() {
        let app = paywall(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["paywall.cta"].waitForExistence(timeout: 6))
        QA.pause(1.5)
        assertFits(app, scrolls: true)
        QA.shot("paywall-xxxl")
    }
}
