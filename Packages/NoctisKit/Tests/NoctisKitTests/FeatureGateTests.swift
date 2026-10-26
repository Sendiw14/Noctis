import Foundation
import Testing

@testable import NoctisCore
@testable import PremiumKit
@testable import SoundKit

// The feature gate (APP_RULES.md R57, R58, R59): what is free and what is Premium, the entitlement transitions through a fake store, the first-frame cache, and
// the free Coach questions' arithmetic. Pure and deterministic: a clock and a calendar are passed in.

private nonisolated let tableFree: [Feature] = [
    .recoveryToday, .recovery7D, .sleepLast3Nights, .sleepWeek, .sleepQualityScore, .insightFeatured, .insightRecentOne, .coachQuestions, .coachHistory,
    .tonightSingleBedtime, .alarm, .breathing, .reflectJournal, .soundsFree, .widgetSmall, .widgetLockCircular, .watchRecoverySleepPages,
    .watchRecoveryComplication, .watchBreathing, .siriRecoverySleepBedtime, .weeklyReviewCover,
]

private nonisolated let tablePremium: [Feature] = [
    .recovery30D, .recovery90D, .recoveryFactorDetail, .sleepMonth, .sleepNightPicker14, .sleepQualityFactors, .sleepConsistencyBalanceTimingDetails,
    .insightAll, .insightRecords, .insightHistory, .insightCategoryFilters, .coachUnlimited, .tonightPersonalizedWindow, .windDownSession, .meditation,
    .soundsPremium, .widgetMediumLargeAndOtherLock, .watchHeartTonightPages, .watchOtherComplications, .siriStartWindDown, .siriAskCoachBeyondFree,
    .weeklyReviewFull, .monthlyReview,
]

struct FeatureTableTests {
    @Test func theFreeAndPremiumSetsAreExactlyTheOnesWritten() {
        #expect(Set(FeatureTable.features(in: .free)) == Set(tableFree) && FeatureTable.features(in: .free).count == tableFree.count)
        #expect(Set(FeatureTable.features(in: .premium)) == Set(tablePremium) && FeatureTable.features(in: .premium).count == tablePremium.count)
        #expect(Feature.allCases.count == tableFree.count + tablePremium.count && Feature.allCases.count == 44, "every feature has one tier")
        #expect(Set(tableFree).isDisjoint(with: Set(tablePremium)))
    }

    @Test func premiumIncludesEverythingAndFreeOnlyTheFreeOnes() {
        for feature in Feature.allCases {
            #expect(FeatureTable.isIncluded(feature, in: .premium), Comment(rawValue: feature.rawValue))
            #expect(FeatureTable.isIncluded(feature, in: .free) == tableFree.contains(feature), Comment(rawValue: feature.rawValue))
        }
    }

    @Test func everyFeatureHasPlainWordsASymbolAndOneArea() {
        var titles: Set<String> = []
        for feature in Feature.allCases {
            let title = FeatureTable.title(of: feature)
            #expect(!title.isEmpty && !FeatureTable.symbol(of: feature).isEmpty, Comment(rawValue: feature.rawValue))
            #expect(titles.insert(title).inserted, Comment(rawValue: "two features are called \"\(title)\""))
            #expect(FeatureArea.allCases.contains(FeatureTable.area(of: feature)))
        }
    }

    @Test func theComparisonListsEveryFeatureExactlyOnceAndSaysIncludedOrNot() {
        let rows = FeatureTable.comparison().flatMap(\.rows)
        #expect(rows.map(\.feature).sorted { $0.rawValue < $1.rawValue } == Feature.allCases.sorted { $0.rawValue < $1.rawValue })
        #expect(Set(rows.map(\.feature)).count == rows.count, "once each")
        for row in rows {
            #expect(row.free == tableFree.contains(row.feature) && row.premium)
            #expect(row.spoken.contains(row.free ? "Free: Included" : "Free: Not included") && row.spoken.hasSuffix("Premium: Included."))
        }
        #expect(FeatureTable.comparison().map(\.area) == FeatureArea.allCases)
    }

    @Test func theSoundsSplitIsTheOneWritten() {
        #expect(FeatureGate.sounds(for: .free) == [.brown, .rain, .ocean])
        #expect(FeatureGate.sounds(for: .premium) == SoundKind.allCases && SoundKind.allCases.count == 6)
        #expect(Set(SoundKind.allCases).subtracting(FeatureGate.sounds(for: .free)) == [.wind, .fireplace, .ambient])
    }

    @Test func eachLockedFeatureOpensAPaywallThatNamesIt() {
        for feature in tablePremium {
            let context = PaywallContext(feature: feature)
            #expect(context != .general, Comment(rawValue: feature.rawValue))
            #expect(!context.line.isEmpty)
        }
        #expect(PaywallContext(feature: .recovery90D).line == "Unlock 90-day Recovery trends")
        #expect(PaywallContext.whatPremiumIncludes.line == "What Premium includes")
        #expect(Set(PaywallContext.allCases.map(\.line)).count == PaywallContext.allCases.count, "no two share a line")
    }
}

// MARK: - The entitlement rules

private nonisolated let now = Date(timeIntervalSince1970: 1_790_258_400)
private nonisolated let yearly = StoreProductID.yearly
private nonisolated let monthly = StoreProductID.monthly
private nonisolated let ids = Set(StoreProductID.all)

private nonisolated func record(
    _ product: String = yearly, verified: Bool = true, revoked: Date? = nil, expires: Date? = now.addingTimeInterval(86_400 * 30), family: Bool = false, trial: Bool = false
) -> EntitlementRecord {
    EntitlementRecord(productID: product, isVerified: verified, revocationDate: revoked, expirationDate: expires, ownership: family ? .familyShared : .purchased, isFreeTrial: trial)
}

private nonisolated func resolve(_ records: [EntitlementRecord], renewal: RenewalRecord? = nil, previous: CachedTier = .free) -> EntitlementState {
    EntitlementResolver.resolve(records: records, renewal: renewal, previous: previous, productIDs: ids, now: now)
}

struct EntitlementResolverTests {
    @Test func nothingIsFreeAndAPurchaseIsPremium() {
        #expect(resolve([]) == .free && resolve([]).tier == .free)
        #expect(resolve([record()]) == .premium(.purchased) && resolve([record(monthly)]) == .premium(.purchased))
        #expect(resolve([record(expires: nil)]) == .premium(.purchased), "no expiry date: current")
    }

    @Test func aFreeTrialIsPremiumAndSaysTrial() {
        #expect(resolve([record(trial: true)]) == .premium(.trial))
        #expect(resolve([record(trial: true), record(monthly)]) == .premium(.purchased), "a paid period wins over a trial")
    }

    @Test func aFamilySharedPlanCountsAsPremium() {
        #expect(resolve([record(family: true)]) == .premium(.familySharing) && resolve([record(family: true)]).tier == .premium)
        #expect(resolve([record(family: true), record()]) == .premium(.purchased), "the person's own plan wins")
    }

    @Test func aRevokedTransactionIsFreeWhateverItsDates() {
        #expect(resolve([record(revoked: now.addingTimeInterval(-60))]) == .free)
        #expect(resolve([record(revoked: now.addingTimeInterval(-60))], previous: .premium) == .previouslyPremiumNowFree)
        #expect(resolve([record(revoked: now.addingTimeInterval(-60)), record(monthly)]) == .premium(.purchased), "another live one still counts")
    }

    @Test func anExpiredTransactionIsFreeAndPremiumBeforeMeansPreviouslyPremium() {
        let expired = record(expires: now.addingTimeInterval(-1))
        #expect(resolve([expired]) == .free)
        #expect(resolve([expired], previous: .premium) == .previouslyPremiumNowFree && resolve([expired], previous: .premium).tier == .free)
        #expect(resolve([], previous: .lapsed) == .previouslyPremiumNowFree, "it stays that way until Premium comes back")
        #expect(resolve([record(expires: now)]) == .free, "an end at this very moment is over")
        #expect(resolve([record(expires: now.addingTimeInterval(1))]) == .premium(.purchased))
    }

    @Test func graceCountsAsPremiumUntilItsOwnEndAndBillingRetryWithNoGraceDoesNot() {
        let expired = record(expires: now.addingTimeInterval(-3600))
        let inGrace = RenewalRecord(state: .inGracePeriod, isInBillingRetry: true, gracePeriodExpirationDate: now.addingTimeInterval(86_400 * 5))
        #expect(resolve([expired], renewal: inGrace) == .premium(.grace))
        let retryAfterGrace = RenewalRecord(state: .inBillingRetryPeriod, isInBillingRetry: true, gracePeriodExpirationDate: now.addingTimeInterval(-60))
        #expect(resolve([expired], renewal: retryAfterGrace, previous: .premium) == .previouslyPremiumNowFree, "grace has ended")
        let retryNoGrace = RenewalRecord(state: .inBillingRetryPeriod, isInBillingRetry: true, gracePeriodExpirationDate: nil)
        #expect(resolve([expired], renewal: retryNoGrace) == .free, "billing retry on its own has no end date, so it is not Premium")
        #expect(resolve([expired], renewal: RenewalRecord(state: .expired, gracePeriodExpirationDate: now.addingTimeInterval(9999))) == .free, "an expired state is not grace")
        #expect(resolve([], renewal: inGrace) == .free, "no transaction at all is not entitled")
        #expect(resolve([record(revoked: now)], renewal: inGrace) == .free, "a revoked one is never revived by grace")
    }

    @Test func anUnverifiedOrForeignTransactionIsIgnored() {
        #expect(resolve([record(verified: false)]) == .free)
        #expect(resolve([record(verified: false)], previous: .premium) == .previouslyPremiumNowFree)
        #expect(resolve([record("com.other.app.product")]) == .free)
        #expect(resolve([record(verified: false), record(monthly)]) == .premium(.purchased), "a verified one beside it still counts")
    }

    @Test func theCachedTierMapsBothWays() {
        for state in [EntitlementState.free, .premium(.trial), .premium(.grace), .premium(.familySharing), .previouslyPremiumNowFree] {
            #expect(CachedTier(state).provisionalState.tier == state.tier)
        }
        #expect(CachedTier.free.provisionalState == .free && CachedTier.premium.provisionalState.tier == .premium && CachedTier.lapsed.provisionalState == .previouslyPremiumNowFree)
    }
}

// MARK: - The manager, through a fake store

nonisolated final class FakeEntitlementClient: EntitlementClient, @unchecked Sendable {
    private let lock = NSLock()
    private var state = (records: [EntitlementRecord](), renewal: RenewalRecord?.none)
    private var continuation: AsyncStream<Void>.Continuation?

    func set(_ records: [EntitlementRecord], renewal: RenewalRecord? = nil) { lock.withLock { state = (records, renewal) } }
    func records() async -> [EntitlementRecord] { lock.withLock { state.records } }
    func renewal() async -> RenewalRecord? { lock.withLock { state.renewal } }
    func updates() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        lock.withLock { self.continuation = continuation }
        return stream
    }
    /// The store says something changed.
    func announce() { lock.withLock { continuation }?.yield() }
}

@MainActor
struct EntitlementManagerTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "noctis.entitlement.\(UUID().uuidString)") ?? .standard }

    private func make(_ client: FakeEntitlementClient, cache: EntitlementCache) -> EntitlementManager {
        EntitlementManager(client: client, cache: cache, clock: { now })
    }

    @Test func theFirstFrameIsTheCachedTierAndTheStoresAnswerReplacesIt() async {
        let cache = EntitlementCache(defaults: defaults())
        cache.write(.premium)
        let client = FakeEntitlementClient()
        let manager = make(client, cache: cache)
        #expect(manager.tier == .premium && !manager.isResolved, "right before the store has answered")
        client.set([])   // the subscription ended while the app was away
        await manager.refresh()
        #expect(manager.isResolved && manager.state == .previouslyPremiumNowFree && manager.tier == .free)
        #expect(cache.read() == .lapsed, "the answer is what the next launch starts from")
    }

    @Test func aFreshInstallStartsFreeAndAPurchaseUnlocksAndIsRemembered() async {
        let cache = EntitlementCache(defaults: defaults())
        let client = FakeEntitlementClient()
        let manager = make(client, cache: cache)
        var changes: [(Tier, Tier)] = []
        manager.onTierChange = { new, old in changes.append((new, old)) }
        #expect(manager.tier == .free && manager.state == .free)
        client.set([record(trial: true)])
        await manager.refresh()
        #expect(manager.state == .premium(.trial) && manager.isInTrial && manager.activeProductID == yearly && cache.read() == .premium)
        #expect(changes.count == 1 && changes[0] == (.premium, .free))
        await manager.refresh()
        #expect(changes.count == 1, "no change, no news")
        client.set([record(revoked: now)])
        await manager.refresh()
        #expect(manager.tier == .free && manager.state == .previouslyPremiumNowFree && changes.count == 2 && changes[1] == (.free, .premium))
        #expect(manager.summary.hasLapsed && !manager.summary.isPremium && manager.summary.detail().contains("still here"))
    }

    @Test func graceFamilyAndTheSummaryAreTold() async {
        let cache = EntitlementCache(defaults: defaults())
        let client = FakeEntitlementClient()
        let manager = make(client, cache: cache)
        client.set([record(expires: now.addingTimeInterval(-60))], renewal: RenewalRecord(state: .inGracePeriod, isInBillingRetry: true, gracePeriodExpirationDate: now.addingTimeInterval(86_400)))
        await manager.refresh()
        #expect(manager.isInGracePeriod && manager.hasActivePremium && manager.summary.isInGracePeriod)
        client.set([record(family: true)])
        await manager.refresh()
        #expect(manager.isFamilyShared && manager.summary.isFamilyShared && manager.summary.detail().contains("Family Sharing"))
    }

    @Test func theStoresUpdatesReachTheTierWithoutAskingAgain() async {
        let cache = EntitlementCache(defaults: defaults())
        let client = FakeEntitlementClient()
        let manager = make(client, cache: cache)
        manager.startListening()
        manager.startListening()
        client.set([record()])
        client.announce()
        _ = await waitFor { manager.tier == .premium }
        #expect(manager.tier == .premium && manager.state == .premium(.purchased))
    }

    @Test func aDebugForcedTierIsNotRememberedAndTheStoreIsNotAsked() async {
        #if DEBUG
        let cache = EntitlementCache(defaults: defaults())
        let client = FakeEntitlementClient()
        client.set([])
        let manager = make(client, cache: cache)
        manager.debugForce(.premium)
        #expect(manager.tier == .premium && manager.isResolved && cache.read() == .free)
        await manager.refresh()
        #expect(manager.tier == .premium, "the store's answer does not undo a forced tier")
        #endif
    }
}

// MARK: - The free Coach questions

private nonisolated func calendar(_ zone: String) -> Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: zone) ?? .gmt
    return value
}

private nonisolated func date(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, _ s: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s)) ?? Date()
}

struct CoachQuotaTests {
    @Test func threeAreFreeEachDayAndEachAnswerUsesOne() {
        let ny = calendar("America/New_York")
        var state = CoachQuotaState()
        let morning = date(ny, 2026, 9, 24, 9)
        #expect(CoachQuota.remaining(state, now: morning, calendar: ny) == 3 && CoachQuota.freeQuestionsPerDay == 3)
        for expected in [2, 1, 0] {
            state = CoachQuota.recording(state, now: morning, calendar: ny)
            #expect(CoachQuota.remaining(state, now: morning, calendar: ny) == expected)
        }
        #expect(state == CoachQuotaState(day: "2026-09-24", used: 3))
        #expect(CoachQuota.line(remaining: 2) == "2 of 3 free questions left today")
        #expect(CoachQuota.usedUpTitle == "You've used today's free questions." && CoachQuota.usedUpDetail == "They reset at midnight.")
    }

    @Test func itResetsAtMidnightByTheLocalCalendar() {
        let ny = calendar("America/New_York")
        let used = CoachQuotaState(day: "2026-09-24", used: 3)
        #expect(CoachQuota.remaining(used, now: date(ny, 2026, 9, 24, 23, 59, 59), calendar: ny) == 0)
        #expect(CoachQuota.remaining(used, now: date(ny, 2026, 9, 25, 0, 0, 0), calendar: ny) == 3, "the second after midnight")
        #expect(CoachQuota.remaining(used, now: date(ny, 2026, 9, 25, 0, 0, 1), calendar: ny) == 3)
        let next = CoachQuota.recording(used, now: date(ny, 2026, 9, 25, 7), calendar: ny)
        #expect(next == CoachQuotaState(day: "2026-09-25", used: 1), "a new day starts the count again")
    }

    @Test func aDayLongerOrShorterThanTwentyFourHoursIsStillOneDay() {
        let ny = calendar("America/New_York")
        // 2026-03-08 has 23 hours (clocks go forward), 2026-11-01 has 25 (they go back, and 1:30 happens twice).
        var spring = CoachQuotaState()
        spring = CoachQuota.recording(spring, now: date(ny, 2026, 3, 8, 1, 30), calendar: ny)
        #expect(CoachQuota.current(spring, now: date(ny, 2026, 3, 8, 23, 59), calendar: ny).used == 1, "the short day")
        #expect(CoachQuota.current(spring, now: date(ny, 2026, 3, 9, 0, 0), calendar: ny).used == 0)
        var fall = CoachQuotaState()
        let firstOneThirty = Date(timeIntervalSince1970: date(ny, 2026, 11, 1, 0, 30).timeIntervalSince1970 + 3600)    // 1:30 EDT
        let secondOneThirty = firstOneThirty.addingTimeInterval(3600)                                                // 1:30 EST
        fall = CoachQuota.recording(fall, now: firstOneThirty, calendar: ny)
        #expect(CoachQuota.dayKey(firstOneThirty, calendar: ny) == CoachQuota.dayKey(secondOneThirty, calendar: ny))
        #expect(CoachQuota.current(fall, now: secondOneThirty, calendar: ny).used == 1, "the repeated hour is the same day")
        #expect(CoachQuota.current(fall, now: date(ny, 2026, 11, 1, 23, 59), calendar: ny).used == 1)
        #expect(CoachQuota.current(fall, now: date(ny, 2026, 11, 2, 0, 0), calendar: ny).used == 0, "the long day")
    }

    @Test func aChangeOfTimeZoneIsNeverAWayToMoreQuestions() {
        let ny = calendar("America/New_York"), tokyo = calendar("Asia/Tokyo"), la = calendar("America/Los_Angeles")
        let evening = date(ny, 2026, 9, 24, 21)    // 9 PM in New York, already the 25th in Tokyo
        let used = CoachQuota.recording(CoachQuota.recording(CoachQuota.recording(CoachQuotaState(), now: evening, calendar: ny), now: evening, calendar: ny), now: evening, calendar: ny)
        #expect(used.day == "2026-09-24" && used.used == 3)
        #expect(CoachQuota.remaining(used, now: evening, calendar: tokyo) == 3, "flying east into the next date is a new day")
        // Back west: the date is the 24th again in Los Angeles at 5 AM, but that day is already counted.
        let lateNightTokyo = date(tokyo, 2026, 9, 25, 1)
        let counted = CoachQuota.recording(CoachQuotaState(), now: lateNightTokyo, calendar: tokyo)
        #expect(CoachQuota.dayKey(lateNightTokyo, calendar: la) == "2026-09-24" && CoachQuota.dayKey(lateNightTokyo, calendar: tokyo) == "2026-09-25")
        #expect(CoachQuota.current(counted, now: lateNightTokyo, calendar: la).day == "2026-09-25", "the later day already counted is kept")
        #expect(CoachQuota.remaining(CoachQuotaState(day: "2026-09-25", used: 3), now: lateNightTokyo, calendar: la) == 0)
    }

    @Test func theCountIsStoredAsADateAndANumberAndNothingElse() {
        let state = CoachQuotaState(day: "2026-09-24", used: 2)
        #expect(state.stored == "2026-09-24|2" && CoachQuotaState(stored: state.stored) == state)
        for bad in ["", "2026-09-24", "2026-09-24|x", "2026-09-24|-1", "a|b|c"] { #expect(CoachQuotaState(stored: bad) == nil, Comment(rawValue: bad)) }
        let defaults = UserDefaults(suiteName: "noctis.quota.\(UUID().uuidString)") ?? .standard
        let store = CoachQuotaStore(defaults: defaults)
        #expect(store.read() == CoachQuotaState())
        store.write(state)
        #expect(store.read() == state)
        defaults.set("garbage", forKey: PremiumKeys.coachQuota)
        #expect(store.read() == CoachQuotaState(), "an unreadable note is a fresh day, never a crash")
        store.clear()
        #expect(defaults.object(forKey: PremiumKeys.coachQuota) == nil)
    }
}

// MARK: - The gate

@MainActor
struct FeatureGateTests {
    @Test func aFixedGateUnlocksExactlyWhatItsTierIncludes() {
        let free = FeatureGate(tier: .free), premium = FeatureGate(tier: .premium)
        for feature in Feature.allCases {
            #expect(premium.isUnlocked(feature), Comment(rawValue: feature.rawValue))
            #expect(free.isUnlocked(feature) == tableFree.contains(feature), Comment(rawValue: feature.rawValue))
        }
        #expect(free.tier == .free && premium.tier == .premium && !free.isPremium && premium.isPremium)
        #expect(Set(SoundKind.allCases.filter(free.isUnlocked(_:))) == [.brown, .rain, .ocean] && SoundKind.allCases.allSatisfy(premium.isUnlocked(_:)))
    }

    @Test func theGateFollowsTheManagersTierAndSaysSoOnAChange() async {
        let cache = EntitlementCache(defaults: UserDefaults(suiteName: "noctis.gate.\(UUID().uuidString)") ?? .standard)
        let client = FakeEntitlementClient()
        let manager = EntitlementManager(client: client, cache: cache, clock: { now })
        var told = 0
        manager.onTierChange = { _, _ in told += 1 }
        let gate = FeatureGate(entitlements: manager, quotaStore: CoachQuotaStore(defaults: UserDefaults(suiteName: "noctis.q.\(UUID().uuidString)") ?? .standard))
        #expect(!gate.isUnlocked(.recovery90D) && gate.tier == .free)
        client.set([record()])
        await manager.refresh()
        #expect(gate.isUnlocked(.recovery90D) && gate.state == .premium(.purchased), "locked views unlock in place")
        #expect(told == 1, "and the earlier listener is still told")
    }

    @Test func freeCoachQuestionsAreCountedPerLocalDayAndPremiumHasNoLimit() {
        let ny = calendar("America/New_York")
        var clock = date(ny, 2026, 9, 24, 9)
        let defaults = UserDefaults(suiteName: "noctis.q.\(UUID().uuidString)") ?? .standard
        let gate = FeatureGate(tier: .free, quotaStore: CoachQuotaStore(defaults: defaults), calendar: { ny }, clock: { clock })
        #expect(gate.coachQuestionsRemaining == 3 && gate.canAskCoach)
        gate.recordCoachAnswer()
        gate.recordCoachAnswer()
        #expect(gate.coachQuestionsRemaining == 1)
        gate.recordCoachAnswer()
        #expect(gate.coachQuestionsRemaining == 0 && !gate.canAskCoach)
        // It is remembered, and a second gate (the app started again) reads the same count.
        let again = FeatureGate(tier: .free, quotaStore: CoachQuotaStore(defaults: defaults), calendar: { ny }, clock: { clock })
        #expect(again.coachQuestionsRemaining == 0)
        clock = date(ny, 2026, 9, 25, 0, 0, 1)
        #expect(gate.coachQuestionsRemaining == 3 && gate.canAskCoach, "after midnight")
        let before = CoachQuotaStore(defaults: defaults).read()
        let premium = FeatureGate(tier: .premium, quotaStore: CoachQuotaStore(defaults: defaults), calendar: { ny }, clock: { clock })
        premium.recordCoachAnswer()
        #expect(premium.coachQuestionsRemaining == nil && premium.canAskCoach && CoachQuotaStore(defaults: defaults).read() == before, "nothing is counted for Premium")
    }
}

// MARK: - What is kept, and what is only for DEBUG

struct FeatureGateRegistrationTests {
    @Test func theTwoKeysAreInTheInventoryAndAreNotInThePreferencesThatResetClears() {
        let keys = DataInventory.shared[.appState].defaultsKeys
        #expect(keys.contains(PremiumKeys.cachedTier) && keys.contains(PremiumKeys.coachQuota))
        #expect(!AppPreferences.allKeys.contains(PremiumKeys.cachedTier) && !AppPreferences.allKeys.contains(PremiumKeys.coachQuota), "Reset preferences must not grant free questions or lock Premium")
        #expect(PremiumKeys.cachedTier.hasPrefix("noctis.") && PremiumKeys.coachQuota.hasPrefix("noctis."), "delete-all removes both")
    }

    @Test func theForcedTierExistsOnlyInDebugBuilds() throws {
        let tokens = ["forceTier", "debugForce", "debugForced"]
        var seen = 0
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources", "App", "Widgets/Home", "Watch/App", "Watch/Widgets"]) {
            var depth = 0                  // nesting of `#if DEBUG`
            var other: [Bool] = []         // whether each open `#if` is the DEBUG one
            for line in file.text.split(separator: "\n", omittingEmptySubsequences: false) {
                let text = line.trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("#if ") {
                    let isDebug = text == "#if DEBUG"
                    other.append(isDebug)
                    if isDebug { depth += 1 }
                } else if text.hasPrefix("#else") || text.hasPrefix("#elseif"), let last = other.last, last {
                    // The other branch of a DEBUG block is the Release one.
                    depth -= 1
                    other[other.count - 1] = false
                } else if text.hasPrefix("#endif"), let last = other.popLast(), last {
                    depth -= 1
                }
                let code = RawDefaultsTests.code(String(line))
                for token in tokens where code.contains(token) {
                    seen += 1
                    #expect(depth > 0, Comment(rawValue: "\(file.path) names \(token) outside #if DEBUG: \(text)"))
                }
            }
        }
        #expect(seen >= 4, "the scan found the DEBUG hooks")
    }
}
