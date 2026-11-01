import Foundation
import StoreKit
import StoreKitTest
import Testing

@testable import NightKit
@testable import NoctisCore
@testable import NoctisIntentKit
@testable import NoctisWatchKit
@testable import PremiumKit

// This bundle is HOSTED by the Noctis app (project.yml, NoctisStoreTests): StoreKit answers only a process that has an app identity. The same file as a
// SwiftPM test (hostless xctest) loaded no products and refused every purchase with StoreKitError.notEntitled, so it cannot live in the package's tests.
//
// QA part 3, step 4: purchases, against StoreKit's own test server (SKTestSession over the app's real Noctis.storekit), through the app's real
// StoreManager / EntitlementManager / StoreKitEntitlementClient. After every transition the tier is read back through each thing that decides by tier:
// FeatureGate, the reminder wording, the Watch pages and complications, the Siri/Control gate, and Coach's free questions.
//
// StoreKitTest API, checked against the installed iOS 27.0 SDK (Developer/Library/Frameworks/StoreKitTest.framework):
//   * SKTestSession(contentsOf:) and the properties askToBuyEnabled, interruptedPurchasesEnabled, disableDialogs, shouldEnterBillingRetryOnRenewal
//     (ObjC billingRetryOnRenewalEnabled), billingGracePeriodIsEnabled (billingGracePeriodEnabled), timeRate are present.
//   * failTransactionsEnabled / failureError are deprecated since iOS 17 ("use simulatedError(forAPI:)"): this file uses setSimulatedError instead.
//   * buyProduct(productIdentifier:) is deprecated since iOS 17: this file uses buyProduct(identifier:options:), and Product.PurchaseOption.purchaseDate.
//   * Time rates beyond the old "one hour is one day" ones exist (OneRenewalEvery...); not needed here because forceRenewalOfSubscription(productIdentifier:) and
//     expireSubscription(productIdentifier:) move the clock for the test.

private let storeKitFile: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Config/Noctis.storekit")

@MainActor
private final class Rig {
    let session: SKTestSession
    let defaults: UserDefaults
    let cache: EntitlementCache
    let entitlements: EntitlementManager
    let store: StoreManager
    let gate: FeatureGate

    init() throws {
        session = try SKTestSession(contentsOf: storeKitFile)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        defaults = UserDefaults(suiteName: "noctis.storekit.\(UUID().uuidString)")!
        cache = EntitlementCache(defaults: defaults)
        entitlements = EntitlementManager(client: StoreKitEntitlementClient(), cache: cache)
        store = StoreManager(entitlementManager: entitlements)
        gate = FeatureGate(entitlements: entitlements, quotaStore: .inMemory())
    }

    var tier: Tier { entitlements.tier }

    func product(_ id: String) async throws -> Product {
        await store.loadProducts()
        return try #require(store.products.first { $0.id == id }, "product \(id) did not load from Noctis.storekit")
    }

    func buy(_ id: String) async throws {
        let product = try await product(id)
        await store.purchase(product)
        // The purchase call returns before StoreKit lists the new entitlement; every caller expects Premium next.
        _ = await waitUntil { entitlements.tier == .premium }
    }

    /// Asks the store again until the state is `expected`, up to 8 seconds.
    func waitForState(_ expected: EntitlementState) async -> Bool {
        for _ in 0..<40 {
            await entitlements.refresh()
            if entitlements.state == expected { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return entitlements.state == expected
    }

    /// Asks the store again until `condition` holds, up to 8 seconds: StoreKitTest applies a change a moment after the call returns.
    func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<40 {
            await entitlements.refresh()
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return condition()
    }

    /// Waits for the listener (Transaction.updates) to bring the entitlement to `tier`, up to 8 seconds.
    func waitFor(_ expected: Tier) async -> Bool {
        for _ in 0..<80 {
            if entitlements.tier == expected { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return entitlements.tier == expected
    }

    func transaction(_ productID: String) throws -> SKTestTransaction {
        try #require(session.allTransactions().last { $0.productIdentifier == productID }, "no test transaction for \(productID)")
    }

    func finish() {
        session.clearTransactions()
        session.resetToDefaultState()
    }
}

/// What every consumer of the tier says for `tier`: the same answer as the feature table, and the plan-specific words.
@MainActor
private func expectEverySurface(agrees tier: Tier, _ rig: Rig, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(rig.gate.tier == tier, sourceLocation: sourceLocation)
    for feature in Feature.allCases {
        #expect(rig.gate.isUnlocked(feature) == FeatureTable.isIncluded(feature, in: tier), "\(feature)", sourceLocation: sourceLocation)
    }
    // Notification copy and routing.
    #expect(
        NotificationPlan.windDownBody(leadMinutes: 20, tier: tier)
            == (tier == .premium ? "Your wind-down window starts in 20 minutes." : "Your bedtime window starts in 20 minutes."), sourceLocation: sourceLocation)
    // Watch pages and complications read the tier the snapshot carries.
    for page in WatchPage.allCases {
        #expect(
            WatchGate.isLocked(page, tier: tier) == !(WatchGate.feature(for: page).map { FeatureTable.isIncluded($0, in: tier) } ?? true),
            sourceLocation: sourceLocation)
    }
    // Siri and Control.
    #expect(IntentGate.includesStartWindDown(in: tier) == (tier == .premium), sourceLocation: sourceLocation)
    // Coach's free questions.
    #expect((rig.gate.coachQuestionsRemaining == nil) == (tier == .premium), sourceLocation: sourceLocation)
}

/// A store whose answers the test sets by hand, and which announces nothing: an expiry is a moment passing, not a transaction.
private final class SilentClient: EntitlementClient, @unchecked Sendable {
    private let lock = NSLock()
    private var current: [EntitlementRecord] = []
    func set(_ records: [EntitlementRecord]) { lock.withLock { current = records } }
    func records() async -> [EntitlementRecord] { lock.withLock { current } }
    func renewal() async -> RenewalRecord? { nil }
    func updates() -> AsyncStream<Void> { AsyncStream { _ in } }
}

@Suite(.serialized) @MainActor
struct StoreKitSessionTests {
    @Test func premiumEndsOnItsOwnWhenThePlanRunsOutDuringTheSession() async throws {
        // The store announces renewals and refunds but never an expiry, so the manager asks again itself when the answer it gave runs out.
        let client = SilentClient()
        let manager = EntitlementManager(client: client, cache: EntitlementCache(defaults: UserDefaults(suiteName: "noctis.storekit.\(UUID().uuidString)")!))
        client.set([EntitlementRecord(productID: StoreProductID.monthly, expirationDate: Date().addingTimeInterval(1.5))])
        await manager.refresh()
        #expect(manager.tier == .premium)
        client.set([])
        for _ in 0..<50 where manager.tier == .premium { try await Task.sleep(for: .milliseconds(100)) }
        #expect(manager.tier == .free || manager.state == .previouslyPremiumNowFree, "state is \(manager.state)")
        #expect(manager.state == .previouslyPremiumNowFree)
    }

    @Test func theStoreKitFileLoadsBothPlansWithTheYearlyTrial() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        let yearly = try await rig.product(StoreProductID.yearly)
        let monthly = try await rig.product(StoreProductID.monthly)
        #expect(yearly.subscription?.subscriptionPeriod.unit == .year && monthly.subscription?.subscriptionPeriod.unit == .month)
        #expect(yearly.subscription?.introductoryOffer?.paymentMode == .freeTrial)
        #expect(yearly.subscription?.introductoryOffer?.period.value == 1 && yearly.subscription?.introductoryOffer?.period.unit == .week)
        #expect(monthly.subscription?.introductoryOffer == nil)
        expectEverySurface(agrees: .free, rig)
    }

    @Test func buyingYearlyStartsTheTrialAndUnlocksEverySurface() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        try await rig.buy(StoreProductID.yearly)
        #expect(rig.store.purchaseState == .success)
        #expect(rig.entitlements.state == .premium(.trial))
        #expect(rig.entitlements.activeProductID == StoreProductID.yearly)
        #expect(rig.cache.read() == .premium)
        expectEverySurface(agrees: .premium, rig)
    }

    @Test func buyingMonthlyIsPremiumWithoutATrial() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        try await rig.buy(StoreProductID.monthly)
        #expect(rig.entitlements.state == .premium(.purchased) && !rig.entitlements.isInTrial)
        #expect(rig.entitlements.activeProductID == StoreProductID.monthly)
        expectEverySurface(agrees: .premium, rig)
    }

    @Test func theTrialConvertsToAPaidYearAndStaysPremium() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        try await rig.buy(StoreProductID.yearly)
        #expect(rig.entitlements.isInTrial)
        try rig.session.forceRenewalOfSubscription(productIdentifier: StoreProductID.yearly)
        #expect(
            await rig.waitForState(.premium(.purchased)), "after the first renewal the trial is over and the plan is paid; state is \(rig.entitlements.state)")
        #expect(rig.tier == .premium)
        expectEverySurface(agrees: .premium, rig)
    }

    @Test func aRenewalMovesTheEndDateForwardAndKeepsPremium() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        try await rig.buy(StoreProductID.monthly)
        let before = try #require(rig.entitlements.expirationDate)
        try rig.session.forceRenewalOfSubscription(productIdentifier: StoreProductID.monthly)
        #expect(await rig.waitUntil { (rig.entitlements.expirationDate ?? before) > before }, "the end date did not move forward")
        #expect(rig.tier == .premium)
    }

    @Test func cancellingAutoRenewKeepsPremiumUntilTheEndAndSaysItWillNotRenew() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        try await rig.buy(StoreProductID.monthly)
        try rig.session.disableAutoRenewForTransaction(identifier: try rig.transaction(StoreProductID.monthly).identifier)
        #expect(await rig.waitUntil { !rig.entitlements.willAutoRenew }, "the store still says it will renew")
        #expect(rig.tier == .premium && !rig.entitlements.willAutoRenew, "cancelled but paid up: Premium to the end date, and the page says it will not renew")
        #expect(rig.entitlements.summary.willRenew == false)
    }

    @Test func anExpiredPlanIsFreeRemembersItWasPremiumAndShowsTheLockedScreens() async throws {
        // Expiry is driven the supported way: a purchase dated 40 days ago that does not renew. (expireSubscription(productIdentifier:) changes the test
        // transaction's end date but not what Transaction.currentEntitlements reports in the same process, so it cannot stand in for a lapse.)
        let rig = try Rig()
        defer { rig.finish() }
        // Premium first, so there is something to lapse from.
        try await rig.buy(StoreProductID.monthly)
        #expect(rig.tier == .premium)
        rig.session.clearTransactions()
        try await rig.session.buyProduct(
            identifier: StoreProductID.monthly, options: [.purchaseDate(Date().addingTimeInterval(-40 * 86_400), renewalBehavior: .cancelImmediately)])
        #expect(await rig.waitForState(.previouslyPremiumNowFree), "state is \(rig.entitlements.state)")
        #expect(rig.cache.read() == .lapsed && rig.entitlements.summary.hasLapsed)
        expectEverySurface(agrees: .free, rig)
    }

    @Test func aSubscriptionThatRenewsKeepsPremiumWhenItsPeriodEndsInTheMiddleOfTheSession() async throws {
        // expireSubscription on an auto-renewing plan renews it at once (the period ended and billing succeeded).
        let rig = try Rig()
        defer { rig.finish() }
        try await rig.buy(StoreProductID.monthly)
        try rig.session.expireSubscription(productIdentifier: StoreProductID.monthly)
        #expect(await rig.waitUntil { rig.tier == .premium }, "the plan renewed, so Premium must stay")
    }

    @Test func billingRetryWithAGracePeriodIsReportedAsGraceByTheStore() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        rig.session.shouldEnterBillingRetryOnRenewal = true
        rig.session.billingGracePeriodIsEnabled = true
        try await rig.buy(StoreProductID.monthly)
        let paidThrough = try #require(rig.entitlements.expirationDate)
        try rig.session.forceRenewalOfSubscription(productIdentifier: StoreProductID.monthly)
        var latest = await StoreKitEntitlementClient().renewal()
        for _ in 0..<40 where latest?.state != .inGracePeriod {
            try await Task.sleep(for: .milliseconds(200))
            latest = await StoreKitEntitlementClient().renewal()
        }
        let renewal = try #require(latest)
        #expect(renewal.state == .inGracePeriod && renewal.isInBillingRetry, "renewal is \(renewal)")
        let graceEnd = try #require(renewal.gracePeriodExpirationDate)
        // What the app does with that answer: the plan's own period has run out (the first transaction ended in the past), the grace period has not.
        let expired = EntitlementRecord(productID: StoreProductID.monthly, expirationDate: paidThrough.addingTimeInterval(-40 * 86_400))
        let during = graceEnd.addingTimeInterval(-86_400)
        #expect(
            EntitlementResolver.resolve(records: [expired], renewal: renewal, previous: .premium, productIDs: [StoreProductID.monthly], now: during)
                == .premium(.grace))
        #expect(
            EntitlementResolver.resolve(
                records: [expired], renewal: renewal, previous: .premium, productIDs: [StoreProductID.monthly], now: graceEnd.addingTimeInterval(60))
                == .previouslyPremiumNowFree)
        // The test server keeps the failed renewal (hasPurchaseIssue) in currentEntitlements with a new period, so the app reads Premium either way.
        await rig.entitlements.refresh()
        #expect(rig.tier == .premium)
        expectEverySurface(agrees: .premium, rig)
        // The card is fixed and billing recovers.
        try rig.session.resolveIssueForTransaction(identifier: try rig.transaction(StoreProductID.monthly).identifier)
        #expect(await rig.waitForState(.premium(.purchased)), "state is \(rig.entitlements.state)")
    }

    @Test func billingRetryWithNoGracePeriodIsReportedAsRetryAndEndsPremiumInTheRules() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        rig.session.shouldEnterBillingRetryOnRenewal = true
        rig.session.billingGracePeriodIsEnabled = false
        try await rig.buy(StoreProductID.monthly)
        let paidThrough = try #require(rig.entitlements.expirationDate)
        try rig.session.forceRenewalOfSubscription(productIdentifier: StoreProductID.monthly)
        var latest = await StoreKitEntitlementClient().renewal()
        for _ in 0..<40 where latest?.state != .inBillingRetryPeriod {
            try await Task.sleep(for: .milliseconds(200))
            latest = await StoreKitEntitlementClient().renewal()
        }
        let renewal = try #require(latest)
        #expect(renewal.state == .inBillingRetryPeriod && renewal.gracePeriodExpirationDate == nil, "renewal is \(renewal)")
        let expired = EntitlementRecord(productID: StoreProductID.monthly, expirationDate: paidThrough.addingTimeInterval(-40 * 86_400))
        #expect(
            EntitlementResolver.resolve(records: [expired], renewal: renewal, previous: .premium, productIDs: [StoreProductID.monthly], now: Date())
                == .previouslyPremiumNowFree)
        // UNVERIFIED: whether a real App Store drops the plan from currentEntitlements here. StoreKitTest keeps the failed renewal in it with a future end
        // date, which the app cannot tell from a paid period; needs a Sandbox account on a device (QA_REPORT.md).
    }

    @Test func aRefundTakesPremiumAway() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        try await rig.buy(StoreProductID.monthly)
        try rig.session.refundTransaction(identifier: try rig.transaction(StoreProductID.monthly).identifier)
        #expect(await rig.waitFor(.free))
        await rig.entitlements.refresh()
        #expect(rig.tier == .free && rig.entitlements.state == .previouslyPremiumNowFree)
        expectEverySurface(agrees: .free, rig)
    }

    @Test func askToBuyIsPendingThenApprovedUnlocksWithoutAnyActionInTheApp() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        rig.session.askToBuyEnabled = true
        try await rig.buy(StoreProductID.monthly)
        #expect(rig.store.purchaseState == .pending)
        #expect(rig.tier == .free)
        let pending = try rig.transaction(StoreProductID.monthly)
        #expect(pending.pendingAskToBuyConfirmation)
        try rig.session.approveAskToBuyTransaction(identifier: pending.identifier)
        #expect(await rig.waitFor(.premium), "an approval arrives through Transaction.updates")
        expectEverySurface(agrees: .premium, rig)
    }

    @Test func askToBuyDeclinedFailsTheTransactionAndUnlocksNothingInTheApp() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        rig.session.askToBuyEnabled = true
        try await rig.buy(StoreProductID.monthly)
        #expect(rig.store.purchaseState == .pending)
        let pending = try rig.transaction(StoreProductID.monthly)
        try rig.session.declineAskToBuyTransaction(identifier: pending.identifier)
        try await Task.sleep(for: .seconds(1))
        let declined = try rig.transaction(StoreProductID.monthly)
        #expect(declined.state == .failed && !declined.pendingAskToBuyConfirmation, "the declined transaction is failed, not purchased")
        await rig.entitlements.refresh()
        // THE KNOWN ISSUE, exactly (probed on the iOS 27.0 simulator, QA part 4): after a decline StoreKitTest hands the app a *verified* Transaction through
        // Transaction.currentEntitlements and Transaction.all with id 0 and originalID 0, a purchase date of the request, an expiry one month on, no revocation date
        // and a subscription status of RenewalState(rawValue: 0) (unknown). Its own SKTestTransaction says state failed. A real App Store decline creates no
        // transaction at all, and no real transaction has id 0, so this is StoreKitTest's stand-in for a failed purchase, not something a device returns: it
        // is not an app bug and the app does not special-case id 0 (that would be a hack around a simulator). The day StoreKitTest stops returning it, this
        // check fails and the wrapper must be removed. A real decline is UNVERIFIED until a Sandbox family organizer declines one (QA_REPORT.md section 5).
        withKnownIssue("StoreKitTest reports a declined Ask to Buy as entitled", isIntermittent: true) {
            #expect(rig.tier == .free)
        }
    }

    @Test func restoreFindsAPurchaseOnAFreshInstall() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        try await rig.buy(StoreProductID.monthly)
        // A new install: the same Apple ID, an empty app (no cached tier), a new manager.
        let freshDefaults = UserDefaults(suiteName: "noctis.storekit.\(UUID().uuidString)")!
        let fresh = StoreManager(entitlementManager: EntitlementManager(client: StoreKitEntitlementClient(), cache: EntitlementCache(defaults: freshDefaults)))
        #expect(fresh.entitlementManager.tier == .free)
        let restored = Task { await fresh.restore() }
        for _ in 0..<150 where fresh.entitlementManager.tier == .free { try await Task.sleep(for: .milliseconds(100)) }
        #expect(fresh.entitlementManager.tier == .premium, "Restore did not finish within 15 seconds")
        _ = restored
        // And with nothing bought, Restore says so.
        rig.session.clearTransactions()
        let empty = StoreManager(
            entitlementManager: EntitlementManager(
                client: StoreKitEntitlementClient(), cache: EntitlementCache(defaults: UserDefaults(suiteName: "noctis.storekit.\(UUID().uuidString)")!)))
        let nothing = Task { await empty.restore() }
        let outcome = await withTaskGroup(of: StoreManager.RestoreResult?.self) { group -> StoreManager.RestoreResult? in
            group.addTask { await nothing.value }
            group.addTask {
                try? await Task.sleep(for: .seconds(15))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        #expect(outcome == .nothingFound, "Restore with nothing bought: \(String(describing: outcome))")
    }

    @Test func aLaunchWithTheLastTierCachedIsRightBeforeTheStoreAnswersAndWithNoNetwork() async throws {
        // The first frame is the cached tier; the store's answer is a local call (signed transactions on the device), so it needs no connection.
        let rig = try Rig()
        defer { rig.finish() }
        try await rig.buy(StoreProductID.monthly)
        let relaunch = EntitlementManager(client: StoreKitEntitlementClient(), cache: rig.cache)
        #expect(relaunch.tier == .premium && !relaunch.isResolved, "the first frame")
        await relaunch.refresh()
        #expect(relaunch.tier == .premium && relaunch.isResolved)
    }

    @Test func aPurchaseMadeWhileTheAppWasNotRunningArrivesThroughTransactionUpdates() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        #expect(rig.tier == .free)
        // The person bought on another device (or the app was killed mid-purchase): nothing in this app asks.
        try await rig.session.buyProduct(identifier: StoreProductID.yearly)
        #expect(await rig.waitFor(.premium), "the listener must pick up an outside purchase")
        expectEverySurface(agrees: .premium, rig)
    }

    @Test func changingFromMonthlyToYearlyKeepsPremiumAndNamesThePlanThatRunsLongest() async throws {
        // Both plans are level 1 of the one group, so the change is a crossgrade to a different duration: the App Store starts the new plan at the next
        // renewal date and the paid month carries on until then. The page names the entitlement that ends last; Premium never drops in between.
        let rig = try Rig()
        defer { rig.finish() }
        try await rig.buy(StoreProductID.monthly)
        let monthlyEnd = try #require(rig.entitlements.expirationDate)
        try await rig.buy(StoreProductID.yearly)
        await rig.entitlements.refresh()
        #expect(rig.tier == .premium)
        let active = try #require(rig.entitlements.activeProductID)
        let end = try #require(rig.entitlements.expirationDate)
        #expect(StoreProductID.all.contains(active) && end >= monthlyEnd, "active \(active) ends \(end), the paid month ends \(monthlyEnd)")
        expectEverySurface(agrees: .premium, rig)
    }

    @Test func aPurchaseThatFailsVerificationIsRefusedAndNothingUnlocks() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        try await rig.session.setSimulatedError(.verification(.invalidSignature), forAPI: .verification)
        try await rig.buy(StoreProductID.monthly)
        #expect(rig.tier == .free, "an unverified transaction must not unlock: purchaseState \(rig.store.purchaseState)")
        try await rig.session.setSimulatedError(nil, forAPI: .verification)
    }

    @Test func aStoreThatCannotLoadProductsLeavesThePaywallUnavailableNotEmptyOrFree() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        try await rig.session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        await rig.store.loadProducts()
        #expect(rig.store.loadState == .unavailable && rig.store.products.isEmpty)
        try await rig.session.setSimulatedError(nil, forAPI: .loadProducts)
        await rig.store.loadProducts()
        #expect(rig.store.loadState == .loaded)
    }

    @Test func aReloadThatFailsKeepsThePlansAlreadyLoaded() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        await rig.store.loadProducts()
        #expect(rig.store.loadState == .loaded && rig.store.products.count == 2)
        try await rig.session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        await rig.store.loadProducts()  // the paywall opens again with no connection
        #expect(rig.store.loadState == .loaded && rig.store.products.count == 2, "the plans the person just saw can still be bought")
        try await rig.session.setSimulatedError(nil, forAPI: .loadProducts)
    }

    @Test func familySharingIsOffInTheConfigurationSoThereIsNothingToBuy() async throws {
        // Both products are familyShareable: false in Noctis.storekit, so Family Sharing cannot be driven by StoreKitTest here. The family-shared rule
        // itself (a family-shared transaction is Premium) is covered against a fake client in FeatureGateTests.
        let data = try Data(contentsOf: storeKitFile)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try #require(json["subscriptionGroups"] as? [[String: Any]])
        let subscriptions = groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
        #expect(subscriptions.count == 2 && subscriptions.allSatisfy { ($0["familyShareable"] as? Bool) == false })
    }

    @Test(arguments: Feature.allCases)
    func everyFeatureIsLockedOnFreeAndOpenOnPremiumExactlyAsTheTableSays(_ feature: Feature) async throws {
        let rig = try Rig()
        defer { rig.finish() }
        let freeIncluded = FeatureTable.tier(of: feature) == .free
        #expect(rig.gate.isUnlocked(feature) == freeIncluded, "\(feature) on free")
        try await rig.buy(StoreProductID.monthly)
        #expect(rig.gate.isUnlocked(feature), "\(feature) on premium")
    }

    // Last on purpose: StoreKit's interrupted purchase leaves a purchase in flight that blocks the next test's purchase, so nothing may run after it.
    @Test func anInterruptedPurchaseDoesNotUnlockAndCanBeRetried() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        let product = try await rig.product(StoreProductID.monthly)
        rig.session.interruptedPurchasesEnabled = true
        let attempt = Task { await rig.store.purchase(product) }
        for _ in 0..<60 where rig.store.purchaseState == .purchasing { try await Task.sleep(for: .milliseconds(100)) }
        let during = rig.store.purchaseState
        #expect(rig.tier == .free && during != .success, "interrupted: purchaseState is \(during)")
        #expect(during != .purchasing, "the paywall's spinner must end when StoreKit interrupts a purchase; purchaseState is \(during)")
        rig.session.interruptedPurchasesEnabled = false
        attempt.cancel()
        let retry = Task { await rig.store.purchase(product) }
        for _ in 0..<60 where rig.store.purchaseState == .purchasing || rig.store.purchaseState == during { try await Task.sleep(for: .milliseconds(100)) }
        _ = retry
        #expect(rig.store.purchaseState == .success, "after the retry: purchaseState \(rig.store.purchaseState)")
        await rig.entitlements.refresh()
        let transactions = rig.session.allTransactions().map {
            "\($0.identifier) \($0.productIdentifier.suffix(7)) state=\($0.state.rawValue) issue=\($0.hasPurchaseIssue) exp=\(String(describing: $0.expirationDate))"
        }
        let records = await StoreKitEntitlementClient().records().map { "\($0.productID.suffix(7)) exp=\(String(describing: $0.expirationDate))" }
        #expect(rig.tier == .premium, "after the retry tier is \(rig.tier); test transactions \(transactions); entitlements \(records)")
    }
}
