import Foundation
import Testing

@testable import HealthProviding
@testable import HomeFeature
@testable import NoctisCore
@testable import NoctisIntentKit
@testable import NoctisWatchKit
@testable import NoctisWidgetKit
@testable import PremiumKit

// A plan that runs out while the app is closed (S1B-C01, P-03): the snapshot carries the end of Premium and every surface outside the app asks one function, at its own
// time, what the plan is. An auto-renewing plan keeps a slack past its end so a paying person whose renewal the app has not yet written is never locked.

private let hour: TimeInterval = 3600

private enum Expiry {
    static let now = WidgetFixture.now
    static var calendar: Calendar { WidgetFixture.calendar }

    static func snapshot(until: Date?, renews: Bool, tier: Tier = .premium) -> WidgetSnapshot {
        var value = WidgetSamples.snapshot(.full, now: now, calendar: calendar, tier: tier)
        value.premiumUntil = until
        value.autoRenews = renews
        return value
    }
}

struct EffectiveTierTests {
    private let end = Expiry.now.addingTimeInterval(5 * hour)

    @Test func aPlanThatDoesNotRenewLocksAtItsEnd() {
        let snapshot = Expiry.snapshot(until: end, renews: false)
        #expect(snapshot.effectiveTier(at: end.addingTimeInterval(-1)) == .premium)
        #expect(snapshot.effectiveTier(at: end) == .free, "at the end, not after")
        #expect(snapshot.effectiveTier(at: end.addingTimeInterval(30 * 86_400)) == .free)
    }

    @Test func aPlanThatRenewsKeepsTheSlackPastItsEnd() {
        let snapshot = Expiry.snapshot(until: end, renews: true)
        let lock = end.addingTimeInterval(WidgetSnapshot.renewalSlack)
        #expect(WidgetSnapshot.renewalSlack == 48 * hour, "the proposed slack; the owner confirms it before release")
        #expect(snapshot.effectiveTier(at: end.addingTimeInterval(1)) == .premium, "a renewal the app has not written yet does not lock a paying person")
        #expect(snapshot.effectiveTier(at: lock.addingTimeInterval(-1)) == .premium)
        #expect(snapshot.effectiveTier(at: lock) == .free)
        #expect(snapshot.premiumLockDate == lock)
    }

    @Test func noEndMeansTheFlagAlone() {
        let premium = Expiry.snapshot(until: nil, renews: false)
        #expect(premium.premiumLockDate == nil)
        #expect(premium.effectiveTier(at: .distantFuture) == .premium, "an unknown end is not a lapse: the app rewrites the snapshot when it learns it")
        let free = Expiry.snapshot(until: end, renews: true, tier: .free)
        #expect(free.premiumLockDate == nil && free.effectiveTier(at: .distantPast) == .free, "a free snapshot never becomes Premium")
    }

    @Test func aFreeSnapshotDropsAnEndItWasGiven() {
        let snapshot = WidgetSnapshot(
            forDay: WidgetDay(year: 2026, month: 9, day: 24), generatedAt: Expiry.now,
            plan: WidgetPlan(wakeMinutes: 420, needMinutes: 480, bedtimeMinutes: 1380), state: .full, tier: .free, premiumUntil: end, autoRenews: true)
        #expect(snapshot.premiumUntil == nil && !snapshot.autoRenews)
        #expect(Expiry.snapshot(until: end, renews: true).with(tier: .free).premiumUntil == nil, "an end belongs to the plan it came with")
        #expect(Expiry.snapshot(until: end, renews: true).with(tier: .premium).premiumUntil == nil)
    }

    @Test func theEndCannotBeClaimedWithoutAnEnd() {
        let snapshot = WidgetSnapshot(
            forDay: WidgetDay(year: 2026, month: 9, day: 24), generatedAt: Expiry.now,
            plan: WidgetPlan(wakeMinutes: 420, needMinutes: 480, bedtimeMinutes: 1380), state: .full, tier: .premium, premiumUntil: nil, autoRenews: true)
        #expect(!snapshot.autoRenews, "renewing at no date says nothing")
    }
}

struct PremiumEndCodingTests {
    private let end = Expiry.now.addingTimeInterval(5 * hour)

    @Test func theEndAndTheRenewalFlagRoundTrip() throws {
        let snapshot = Expiry.snapshot(until: end, renews: true)
        let decoded = try #require(WidgetSnapshot.decode(snapshot.encoded()))
        #expect(decoded.premiumUntil.map { Int($0.timeIntervalSince1970) } == Int(end.timeIntervalSince1970), "whole seconds, like every other time in the file")
        #expect(decoded.autoRenews)
        #expect(decoded.effectiveTier(at: end.addingTimeInterval(1)) == .premium)
    }

    @Test func aSnapshotWrittenBeforeTheEndExistedStillReadsAndHasNone() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: Expiry.snapshot(until: end, renews: true).encoded()) as? [String: Any])
        object.removeValue(forKey: "pu")
        object.removeValue(forKey: "ar")
        let decoded = try #require(WidgetSnapshot.decode(JSONSerialization.data(withJSONObject: object)))
        #expect(decoded.version == WidgetSnapshot.currentVersion && decoded.tier == .premium)
        #expect(decoded.premiumUntil == nil && !decoded.autoRenews, "additive to version 2, so an older file is never rejected")
    }

    @Test func anEndThatCannotBeReadIsNoEndAndNeverUnlocksAnything() throws {
        for junk in [NSNull(), "tomorrow", [1], true] as [Any] {
            var object = try #require(try JSONSerialization.jsonObject(with: Expiry.snapshot(until: end, renews: true).encoded()) as? [String: Any])
            object["pu"] = junk
            object["ar"] = junk
            let decoded = try #require(WidgetSnapshot.decode(JSONSerialization.data(withJSONObject: object)), Comment(rawValue: "\(junk)"))
            #expect(decoded.premiumUntil == nil && !decoded.autoRenews, Comment(rawValue: "\(junk)"))
        }
    }

    @Test func theSnapshotStaysWellUnderItsCap() throws {
        let data = try Expiry.snapshot(until: end, renews: true).encoded()
        #expect(data.count < WidgetSnapshot.maximumBytes / 2, "\(data.count) bytes")
        #expect(WidgetSnapshot.maximumBytes == 3072)
        let directory = try WidgetFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(WidgetSnapshotStore(directory: directory).save(Expiry.snapshot(until: end, renews: true)))
    }

    @Test func aFreeSnapshotAddsNoEndToTheFile() throws {
        let text = String(decoding: try Expiry.snapshot(until: nil, renews: false, tier: .free).encoded(), as: UTF8.self)
        #expect(!text.contains("\"pu\""), Comment(rawValue: text))
    }
}

struct ExpiryTimelineTests {
    private let now = Expiry.now

    @Test func theWidgetLocksAtTheMomentThePlanRunsOutWithTheAppClosed() throws {
        let end = now.addingTimeInterval(3 * hour)
        let plan = WidgetTimelineBuilder.build(snapshot: Expiry.snapshot(until: end, renews: false), now: now, calendar: Expiry.calendar)
        let lockEntry = try #require(plan.entries.first { $0.date == end }, "an entry is placed at the end")
        let before = try #require(plan.entries.last { $0.date < end })
        #expect(!WidgetGate.isLocked(before, in: .medium), "until then Premium widgets show their numbers")
        #expect(WidgetGate.isLocked(lockEntry, in: .medium), "from then on the family is the calm locked view")
        #expect(!WidgetGate.isLocked(lockEntry, in: .small), "the free families are still drawn")
    }

    @Test func aRenewingPlanLocksAfterTheSlackNotAtTheEnd() throws {
        let end = now.addingTimeInterval(-hour)
        let lock = end.addingTimeInterval(WidgetSnapshot.renewalSlack)
        let plan = WidgetTimelineBuilder.build(snapshot: Expiry.snapshot(until: end, renews: true), now: now, calendar: Expiry.calendar)
        #expect(plan.entries.allSatisfy { $0.date < lock || WidgetGate.isLocked($0, in: .medium) })
        #expect(!WidgetGate.isLocked(plan.entries[0], in: .medium), "an hour past the end of a renewing plan is still Premium")
        #expect(!plan.entries.contains { $0.date == lock }, "the slack ends past this timeline, which asks again at its horizon")
    }

    @Test func aPlanAlreadyPastItsLockIsLockedFromTheFirstEntry() throws {
        let plan = WidgetTimelineBuilder.build(
            snapshot: Expiry.snapshot(until: now.addingTimeInterval(-hour), renews: false), now: now, calendar: Expiry.calendar)
        #expect(WidgetGate.isLocked(plan.entries[0], in: .medium))
    }

    @Test func noEndAddsNoEntryAndAFarEndAddsNone() {
        let plain = WidgetTimelineBuilder.build(snapshot: Expiry.snapshot(until: nil, renews: false), now: now, calendar: Expiry.calendar)
        let far = WidgetTimelineBuilder.build(
            snapshot: Expiry.snapshot(until: now.addingTimeInterval(30 * 86_400), renews: false), now: now, calendar: Expiry.calendar)
        let free = WidgetTimelineBuilder.build(snapshot: Expiry.snapshot(until: nil, renews: false, tier: .free), now: now, calendar: Expiry.calendar)
        #expect(plain.entries.map(\.date) == far.entries.map(\.date) && plain.entries.map(\.date) == free.entries.map(\.date), "the same moments as before")
        #expect(plain.reloadAfter <= now.addingTimeInterval(WidgetTimelineBuilder.horizon))
    }

    @Test func theWatchComplicationsUseTheSameMoments() throws {
        let end = now.addingTimeInterval(2 * hour)
        let dates = WatchComplicationSchedule.dates(snapshot: Expiry.snapshot(until: end, renews: false), now: now, calendar: Expiry.calendar)
        #expect(dates.entries.contains { $0.date == end })
        let snapshot = Expiry.snapshot(until: end, renews: false)
        #expect(WatchComplicationSchedule.window(.sleep, snapshot: snapshot, from: end, calendar: Expiry.calendar) == nil, "a locked kind promotes nothing")
        #expect(WatchComplicationSchedule.window(.sleep, snapshot: snapshot, from: end.addingTimeInterval(-hour), calendar: Expiry.calendar) != nil)
    }
}

struct ExpirySurfaceTests {
    private let now = Expiry.now
    private var end: Date { now.addingTimeInterval(2 * hour) }

    @Test func siriAndShortcutsSeeTheLapse() {
        let snapshot = Expiry.snapshot(until: end, renews: false)
        func tier(at date: Date) -> Tier { IntentEnvironment(snapshot: { snapshot }, now: { date }).tier() }
        #expect(tier(at: now) == .premium)
        #expect(tier(at: end) == .free, "a Shortcut run after the end gets the free plan, with the app closed")
    }

    @Test func theSpokenBedtimeFollowsTheClock() {
        let snapshot = Expiry.snapshot(until: end, renews: false)
        let format = WidgetFormat(calendar: Expiry.calendar, locale: Locale(identifier: "en_US"))
        let window = WidgetSpoken.bedtime(snapshot, now: now, format: format)
        let single = WidgetSpoken.bedtime(snapshot, now: end, format: format)
        #expect(window.contains("window") && !single.contains("window"), "\(window) / \(single)")
    }

    @Test func theWatchLocksItsPremiumPagesWithoutThePhone() {
        let snapshot = Expiry.snapshot(until: end, renews: false)
        let format = WidgetFormat(calendar: Expiry.calendar, locale: Locale(identifier: "en_US"))
        let before = WatchPages.heart(WatchPageInput(snapshot: snapshot, now: now, format: format))
        let after = WatchPages.heart(WatchPageInput(snapshot: snapshot, now: end, format: format))
        #expect(before.locked == nil && after.locked != nil, "the Heart page locks at the end, from the snapshot alone")
        let tonight = WatchPages.tonight(WatchPageInput(snapshot: snapshot, now: end, format: format))
        #expect(tonight.locked != nil)
    }

    @Test func aRenewalSlackKeepsTheWatchUnlockedForAPayingPerson() {
        let snapshot = Expiry.snapshot(until: end, renews: true)
        let format = WidgetFormat(calendar: Expiry.calendar, locale: Locale(identifier: "en_US"))
        #expect(WatchPages.heart(WatchPageInput(snapshot: snapshot, now: end.addingTimeInterval(hour), format: format)).locked == nil)
    }
}

struct SnapshotTierReadersTests {
    /// Nothing outside the snapshot reads its `tier` flag directly: every reader asks `effectiveTier(at:)`, so no surface can keep Premium past its end by
    /// forgetting the clock.
    @Test func everyReaderAsksTheOneFunction() {
        let files = RawDefaultsTests.swiftFiles(under: [
            "Widgets/Home", "Watch/App", "Watch/Widgets", "Packages/NoctisKit/Sources/NoctisWidgetKit", "Packages/NoctisKit/Sources/NoctisWatchKit",
            "Packages/NoctisKit/Sources/NoctisIntentKit", "Packages/NoctisKit/Sources/AppRoot",
        ])
        #expect(!files.isEmpty)
        let pattern = #/\bsnapshot\??\.tier\b/#
        for file in files where !file.path.hasSuffix("WidgetSnapshot.swift") {
            let code = RawDefaultsTests.code(file.text)
            #expect(code.firstMatch(of: pattern) == nil, Comment(rawValue: "\(file.path) reads the snapshot's tier flag; ask effectiveTier(at:)"))
        }
    }
}

private actor WindowBox {
    var value = PremiumWindow()
    func set(_ window: PremiumWindow) { value = window }
}

struct PremiumWindowPublishingTests {
    private let now = WidgetFixture.now

    private func bench(window: WindowBox) throws -> (WidgetPublisher, WidgetSnapshotStore, URL) {
        let directory = try WidgetFixture.directory()
        let store = WidgetSnapshotStore(directory: directory)
        let inputs = WidgetInputSource(profile: { UserProfileSnapshot() })
        inputs.setTier { .premium }
        inputs.setPremiumWindow { await window.value }
        let clock = now
        return (WidgetPublisher(store: store, inputs: inputs, clock: { clock }, calendar: WidgetFixture.calendar), store, directory)
    }

    private func repository(_ publisher: WidgetPublisher) -> HomeRepository {
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let clock = now
        return HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock }, widgets: publisher)
    }

    @Test func theEndIsWrittenAndARenewalWritesItAgain() async throws {
        let box = WindowBox()
        let first = now.addingTimeInterval(5 * hour)
        await box.set(PremiumWindow(until: first, autoRenews: true))
        let (publisher, store, directory) = try bench(window: box)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = await repository(publisher).refresh(profile: UserProfileSnapshot())
        #expect(store.load()?.premiumUntil.map { Int($0.timeIntervalSince1970) } == Int(first.timeIntervalSince1970) && store.load()?.autoRenews == true)

        let renewed = first.addingTimeInterval(30 * 86_400)
        await box.set(PremiumWindow(until: renewed, autoRenews: true))
        await publisher.republish()
        #expect(store.load()?.premiumUntil.map { Int($0.timeIntervalSince1970) } == Int(renewed.timeIntervalSince1970), "a renewal with the same tier still reaches the file")

        await box.set(PremiumWindow(until: renewed, autoRenews: false))
        await publisher.republish()
        #expect(store.load()?.autoRenews == false, "a cancellation stops the slack")
    }

    @Test func aWriteBeforeTheStoreHasAnsweredKeepsTheEndAlreadyWritten() async throws {
        let box = WindowBox()
        let end = now.addingTimeInterval(5 * hour)
        await box.set(PremiumWindow(until: end, autoRenews: false))
        let (publisher, store, directory) = try bench(window: box)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = repository(publisher)
        _ = await repository.refresh(profile: UserProfileSnapshot())
        await box.set(PremiumWindow())
        _ = await repository.refresh(profile: UserProfileSnapshot())
        await publisher.republish()
        #expect(store.load()?.premiumUntil != nil, "an unknown end after a launch does not erase a known one")
    }

    @Test func aFreePersonHasNoEndWhateverTheStoreSaid() async throws {
        let directory = try WidgetFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        let inputs = WidgetInputSource(profile: { UserProfileSnapshot() })
        inputs.setPremiumWindow { PremiumWindow(until: Date(timeIntervalSince1970: 4_000_000_000), autoRenews: true) }
        let clock = now
        let publisher = WidgetPublisher(store: store, inputs: inputs, clock: { clock }, calendar: WidgetFixture.calendar)
        _ = await repository(publisher).refresh(profile: UserProfileSnapshot())
        #expect(store.load()?.tier == .free && store.load()?.premiumUntil == nil)
    }
}

@MainActor
struct PremiumWindowFromTheStoreTests {
    private let now = Expiry.now

    private func manager(_ client: FakeEntitlementClient) -> EntitlementManager {
        let defaults = UserDefaults(suiteName: "noctis.expiry.\(UUID().uuidString)") ?? .standard
        let clock = now
        return EntitlementManager(client: client, cache: EntitlementCache(defaults: defaults), clock: { clock })
    }

    private func record(expires: Date) -> EntitlementRecord { EntitlementRecord(productID: StoreProductID.yearly, expirationDate: expires) }

    @Test func thePlansEndAndWhetherItRenewsComeFromTheStore() async {
        let client = FakeEntitlementClient()
        let end = now.addingTimeInterval(10 * 86_400)
        let manager = manager(client)
        #expect(manager.premiumUntil == nil && !manager.premiumAutoRenews, "free: nothing to run out")
        client.set([record(expires: end)], renewal: RenewalRecord(state: .subscribed, willAutoRenew: true))
        await manager.refresh()
        #expect(manager.premiumUntil == end && manager.premiumAutoRenews)
        client.set([record(expires: end)], renewal: RenewalRecord(state: .subscribed, willAutoRenew: false))
        await manager.refresh()
        #expect(manager.premiumUntil == end && !manager.premiumAutoRenews, "cancelled: it ends at its end, with no slack")
    }

    @Test func aGracePeriodEndsAtItsOwnEndAndDoesNotRenewUntilThePaymentIsFixed() async {
        let client = FakeEntitlementClient()
        let graceEnd = now.addingTimeInterval(3 * 86_400)
        let manager = manager(client)
        client.set(
            [record(expires: now.addingTimeInterval(-60))],
            renewal: RenewalRecord(state: .inGracePeriod, isInBillingRetry: true, gracePeriodExpirationDate: graceEnd))
        await manager.refresh()
        #expect(manager.isInGracePeriod && manager.premiumUntil == graceEnd && !manager.premiumAutoRenews)
    }

    @Test func aRenewalThatKeepsTheTierStillTellsTheSnapshotWriter() async {
        let client = FakeEntitlementClient()
        let manager = manager(client)
        var windowChanges = 0
        var tierChanges = 0
        manager.onPremiumWindowChange = { windowChanges += 1 }
        manager.onTierChange = { _, _ in tierChanges += 1 }
        client.set([record(expires: now.addingTimeInterval(86_400))], renewal: RenewalRecord(state: .subscribed))
        await manager.refresh()
        #expect(tierChanges == 1 && windowChanges == 0, "a new plan is the tier change's news, not a second one")
        await manager.refresh()
        #expect(windowChanges == 0, "nothing moved")
        client.set([record(expires: now.addingTimeInterval(31 * 86_400))], renewal: RenewalRecord(state: .subscribed))
        await manager.refresh()
        #expect(tierChanges == 1 && windowChanges == 1, "a renewal moves the end")
        client.set([record(expires: now.addingTimeInterval(31 * 86_400))], renewal: RenewalRecord(state: .subscribed, willAutoRenew: false))
        await manager.refresh()
        #expect(windowChanges == 2, "a cancellation stops the slack")
    }

    @Test func aPaymentThatCannotBeTakenIsSaidPlainly() async {
        let client = FakeEntitlementClient()
        let manager = manager(client)
        client.set(
            [record(expires: now.addingTimeInterval(-3600))],
            renewal: RenewalRecord(state: .inBillingRetryPeriod, isInBillingRetry: true, gracePeriodExpirationDate: nil))
        await manager.refresh()
        #expect(manager.tier == .free && manager.hasPaymentProblem && manager.summary.hasPaymentProblem)
        let detail = manager.summary.detail()
        #expect(detail.contains("payment") && detail.contains("Manage subscription") && detail.contains("still here"), Comment(rawValue: detail))
        client.set([record(expires: now.addingTimeInterval(30 * 86_400))], renewal: RenewalRecord(state: .subscribed))
        await manager.refresh()
        #expect(!manager.hasPaymentProblem && manager.tier == .premium, "paid: back, and no problem is shown")
    }

    @Test func aPausedPlanIsNotCalledTheFreePlanAnywhereOnThePage() {
        let paused = SubscriptionSummary(hasPaymentProblem: true)
        #expect(paused.headline == "Premium paused" && paused.pageSummary == "Your payment needs attention.")
        let free = SubscriptionSummary.free
        #expect(free.headline == "Free" && free.pageSummary == "You're on the free plan.", "the ordinary free plan reads exactly as before")
        let premium = SubscriptionSummary(isPremium: true, plan: .yearly)
        #expect(premium.headline == "Premium · Yearly" && premium.pageSummary == "You have Premium.")
        #expect(SubscriptionSummary(isPremium: true, plan: .yearly, isInGracePeriod: true).pageSummary == "You have Premium.")
    }

    @Test func aFreePersonWithNoBillingTroubleSeesNoProblem() async {
        let client = FakeEntitlementClient()
        let manager = manager(client)
        client.set([], renewal: RenewalRecord(state: .expired))
        await manager.refresh()
        #expect(!manager.hasPaymentProblem)
        #expect(!SubscriptionSummary(isPremium: true, hasPaymentProblem: true).hasPaymentProblem, "a person with Premium has no paused Premium")
    }
}

struct PremiumWiringTests {
    private func container() throws -> String {
        try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/AppRoot/AppContainer.swift"), encoding: .utf8)
    }

    @Test func theSnapshotIsGivenTheEndAndRewrittenWhenARenewalMovesIt() throws {
        let text = try container()
        #expect(text.contains("widgetInputs.setPremiumWindow {"), "the publisher asks the store's answer for the end")
        #expect(text.contains("store.entitlementManager.premiumUntil") && text.contains("store.entitlementManager.premiumAutoRenews"))
        let hook = try #require(text.range(of: "store.entitlementManager.onPremiumWindowChange = {"))
        #expect(text[hook.upperBound...].prefix(120).contains("widgetPublisher.republish()"))
    }

    @Test func aBackgroundWakeRefreshesHomeBeforeItAsksTheStore() throws {
        let text = try container()
        let refresher = try #require(text.range(of: "let backgroundRefresher = BackgroundRefresher("))
        let body = String(text[refresher.upperBound...].prefix(1800))
        let helper = try #require(body.range(of: "BackgroundRefresher.healthThenPlan("))
        let home = try #require(body.range(of: "health: { _ = await homeRepository.refresh("))
        let store = try #require(body.range(of: "plan: { await store.entitlementManager.refresh() }"))
        #expect(helper.lowerBound < home.lowerBound && home.lowerBound < store.lowerBound, "Home is the health work, the store is the plan")
    }

    @Test func aPlanFoundChangedAfterTheHomeRefreshRewritesTheSnapshotItself() async throws {
        // The store is asked after Home has published, so its answer must reach the snapshot without another Home refresh.
        let defaults = UserDefaults(suiteName: "noctis.wake.\(UUID().uuidString)") ?? .standard
        let client = FakeEntitlementClient()
        let clock = Expiry.now
        let manager = await EntitlementManager(client: client, cache: EntitlementCache(defaults: defaults), clock: { clock })
        let directory = try WidgetFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        let inputs = WidgetInputSource(profile: { UserProfileSnapshot() })
        inputs.setTier { await manager.tier }
        inputs.setPremiumWindow { await PremiumWindow(until: manager.premiumUntil, autoRenews: manager.premiumAutoRenews) }
        let publisher = WidgetPublisher(store: store, inputs: inputs, clock: { clock }, calendar: WidgetFixture.calendar)
        await MainActor.run { manager.onTierChange = { _, _ in Task { await publisher.republish() } } }
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: clock, calendar: Fixture.calendar(), startAuthorized: true)
        let home = HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock }, widgets: publisher)

        _ = await home.refresh(profile: UserProfileSnapshot())
        #expect(store.load()?.tier == .free, "Health first: the numbers are written before the store is asked")

        let end = clock.addingTimeInterval(10 * 86_400)
        client.set([EntitlementRecord(productID: StoreProductID.yearly, expirationDate: end)], renewal: RenewalRecord(state: .subscribed))
        await manager.refresh()
        _ = await waitFor { store.load()?.tier == .premium }
        let written = try #require(store.load())
        #expect(written.tier == .premium && written.premiumUntil.map { Int($0.timeIntervalSince1970) } == Int(end.timeIntervalSince1970))
    }
}

// R-01 under a slow or failing store: the wake's budget ends, and the Health numbers are already written.
struct WakeBudgetTests {
    private nonisolated final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.withLock { items.append(item) } }
        var all: [String] { lock.withLock { items } }
    }

    /// Work that waits until the test lets it go (no guessed durations).
    private nonisolated final class Gate: @unchecked Sendable {
        let stream: AsyncStream<Void>
        private let continuation: AsyncStream<Void>.Continuation
        init() { (stream, continuation) = AsyncStream<Void>.makeStream() }
        func wait() async { for await _ in stream {} }
        func release() { continuation.finish() }
    }

    @Test func aStoreThatNeverAnswersDoesNotCostTheHealthRefresh() async {
        let log = Log()
        let hang = Gate()
        let planStarted = Gate()
        let work = BackgroundRefresher.healthThenPlan(
            health: { log.add("health") },
            plan: {
                log.add("plan started")
                planStarted.release()
                await hang.wait()
                log.add("plan finished")
            })
        // The budget runs out exactly when the store has been asked and has not answered: no guessed duration, so a busy machine cannot change the order.
        let refresher = BackgroundRefresher(
            isOnboarded: { true }, isAuthorized: { true }, refresh: work, minimumInterval: 0, timeBudget: 20, sleep: { _ in await planStarted.wait() })
        let outcome = await refresher.handleWake()
        #expect(outcome == .timedOut, "the wake ends at its budget so HealthKit is let go")
        #expect(log.all == ["health", "plan started"], "Health was written before the store was asked: \(log.all)")
        hang.release()
    }

    @Test func aSlowHealthReadIsNeverHeldUpByTheStore() async {
        let log = Log()
        let slow = Gate()
        let work = BackgroundRefresher.healthThenPlan(
            health: {
                log.add("health started")
                await slow.wait()
                log.add("health")
            },
            plan: { log.add("plan") })
        let refresher = BackgroundRefresher(isOnboarded: { true }, isAuthorized: { true }, refresh: work, minimumInterval: 0, timeBudget: 30)
        let wake = Task { await refresher.handleWake() }
        _ = await waitFor { log.all == ["health started"] }
        #expect(log.all == ["health started"], "the store is not asked while Health is still being read: \(log.all)")
        slow.release()
        #expect(await wake.value == .refreshed)
        #expect(log.all == ["health started", "health", "plan"])
    }

    @Test func aStoreThatFailsLeavesTheWakeFinishedAndHealthWritten() async {
        let log = Log()
        let work = BackgroundRefresher.healthThenPlan(health: { log.add("health") }, plan: { log.add("plan answered nothing") })
        let refresher = BackgroundRefresher(isOnboarded: { true }, isAuthorized: { true }, refresh: work, minimumInterval: 0, timeBudget: 5)
        #expect(await refresher.handleWake() == .refreshed)
        #expect(log.all == ["health", "plan answered nothing"])
    }
}
