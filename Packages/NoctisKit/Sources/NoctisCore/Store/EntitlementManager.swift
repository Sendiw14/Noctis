import Foundation
import Observation
import PremiumKit

/// What the person is entitled to, kept current (APP_RULES.md R57). `EntitlementResolver` (pure, in `PremiumKit`) turns what the store reports into an
/// `EntitlementState`; this asks the store (`EntitlementClient`: `Transaction.currentEntitlements` and the renewal info), listens for changes, remembers the last
/// tier for the first frame, and says when the tier changes. Only verified transactions count: a revoked or expired one is free, a grace period counts as
/// Premium until its own end, a family-shared plan counts as Premium.
///
/// Gating is presentation only: nothing here, or in anything that reads it, deletes or hides by deleting what a person recorded.
@Observable
@MainActor
public final class EntitlementManager {
    public private(set) var state: EntitlementState
    /// The store has answered at least once this launch (before that, `state` is the cached tier).
    public private(set) var isResolved = false
    public private(set) var expirationDate: Date?
    public private(set) var willAutoRenew = true
    public private(set) var activeProductID: String?
    /// The end of the grace period while the plan is in one (the plan's own end has passed by then).
    public private(set) var gracePeriodEnd: Date?
    /// Billing failed and is being retried with no grace period: Premium is paused until the payment goes through.
    public private(set) var hasPaymentProblem = false
    #if DEBUG
    /// `-mockSubscription`: a fixed answer for a screenshot, since the simulator's StoreKit has no purchase.
    public private(set) var debugSummary: SubscriptionSummary?
    /// `-forceTier free|premium`: the tier is fixed, whatever the store says. DEBUG only.
    private var debugForced = false
    #endif

    private let client: any EntitlementClient
    private let cache: EntitlementCache
    private let clock: @Sendable () -> Date
    private var listener: Task<Void, Never>?
    /// Wakes the manager when the answer it just gave runs out (the plan's end, or the end of a grace period), because the store announces a renewal or
    /// a refund but never an expiry: without it Premium would last until the next launch (QA_LEDGER.md).
    private var dueRefresh: Task<Void, Never>?
    /// Counts the refreshes that have started; only the latest one may apply its answer.
    private var refreshCount = 0
    /// Told when the tier changes: the new tier and the old.
    @ObservationIgnored public var onTierChange: (@MainActor (_ new: Tier, _ old: Tier) -> Void)?
    /// Told when what the surfaces outside the app are given changes without the tier changing: a renewal moves the end, a cancellation stops it renewing (S1B-C01).
    @ObservationIgnored public var onPremiumWindowChange: (@MainActor () -> Void)?

    public init(
        client: any EntitlementClient = StoreKitEntitlementClient(), cache: EntitlementCache = EntitlementCache(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.cache = cache
        self.clock = clock
        state = cache.read().provisionalState
    }

    public var tier: Tier { state.tier }

    /// When Premium access ends, as the snapshot carries it for widgets, complications, Siri and the Watch: the end of the grace period while in one, else the plan's
    /// end. Nil when free or not yet known (the store has not answered since launch).
    public var premiumUntil: Date? {
        guard tier == .premium else { return nil }
        return isInGracePeriod ? (gracePeriodEnd ?? expirationDate) : expirationDate
    }

    /// Whether the plan renews itself at `premiumUntil`: not in a grace period (a renewal waits for the payment to be fixed) and not after a cancellation.
    public var premiumAutoRenews: Bool { tier == .premium && !isInGracePeriod && willAutoRenew }
    public var hasActivePremium: Bool { tier == .premium }
    /// Premium content is served through a billing grace period (Apple's guidance), so this is the same as `hasActivePremium`.
    public var hasAccess: Bool { hasActivePremium }
    public var isInGracePeriod: Bool { state == .premium(.grace) }
    public var isInTrial: Bool { state == .premium(.trial) }
    public var isFamilyShared: Bool { state == .premium(.familySharing) }

    /// What the Subscription page shows.
    public var summary: SubscriptionSummary {
        #if DEBUG
        if let debugSummary { return debugSummary }
        #endif
        return SubscriptionSummary(
            isPremium: hasActivePremium, plan: activeProductID.flatMap(SubscriptionSummary.Plan.init(productID:)), isTrial: isInTrial, willRenew: willAutoRenew,
            endDate: expirationDate, isInGracePeriod: isInGracePeriod, isFamilyShared: isFamilyShared, hasLapsed: state == .previouslyPremiumNowFree,
            hasPaymentProblem: hasPaymentProblem
        )
    }

    #if DEBUG
    public func debugSet(_ summary: SubscriptionSummary) {
        debugSummary = summary
        let source: PremiumSource = summary.isFamilyShared ? .familySharing : summary.isInGracePeriod ? .grace : summary.isTrial ? .trial : .purchased
        set(summary.isPremium ? .premium(source) : .free, remember: false)
    }

    /// `-forceTier`: Premium or free, fixed, with nothing asked of the store.
    public func debugForce(_ tier: Tier) {
        debugForced = true
        set(tier == .premium ? .premium(.purchased) : .free, remember: false)
        isResolved = true
    }
    #endif

    /// Starts listening for the store's changes (a renewal, a refund, a purchase on another device). Called once, at launch.
    public func startListening() {
        guard listener == nil else { return }
        let updates = client.updates()
        listener = Task { [weak self] in
            for await _ in updates { await self?.refresh() }
        }
    }

    /// Asks the store and works out the state; the answer is remembered for the next first frame.
    public func refresh() async {
        #if DEBUG
        if debugForced || debugSummary != nil { return }
        #endif
        refreshCount += 1
        let ticket = refreshCount
        let records = await client.records()
        let renewal = await client.renewal()
        // A refresh that started after this one asked for a newer answer: this one is out of date, and applying it last would undo a refund or a purchase.
        guard ticket == refreshCount else { return }
        let tierBefore = state.tier
        let windowBefore = (premiumUntil, premiumAutoRenews)
        let resolved = EntitlementResolver.resolve(
            records: records, renewal: renewal, previous: cache.read(), productIDs: Set(StoreProductID.all), now: clock()
        )
        // The newest period wins when more than one is current.
        let valid = records.filter { $0.isVerified && $0.revocationDate == nil && StoreProductID.all.contains($0.productID) }
        let newest = valid.max { ($0.expirationDate ?? .distantPast) < ($1.expirationDate ?? .distantPast) }
        expirationDate = resolved.tier == .premium ? newest?.expirationDate : nil
        activeProductID = resolved.tier == .premium ? newest?.productID : nil
        willAutoRenew = renewal?.willAutoRenew ?? true
        gracePeriodEnd = resolved == .premium(.grace) ? renewal?.gracePeriodExpirationDate : nil
        hasPaymentProblem = resolved.tier == .free && renewal.map { $0.state == .inBillingRetryPeriod || $0.isInBillingRetry } == true
        isResolved = true
        set(resolved)
        if (premiumUntil, premiumAutoRenews) != windowBefore, resolved.tier == tierBefore { onPremiumWindowChange?() }
        scheduleDueRefresh(resolved: resolved, expiration: expirationDate, graceEnd: renewal?.gracePeriodExpirationDate)
    }

    /// One task, replaced on every answer: asks again a second after the moment the Premium just reported ends.
    private func scheduleDueRefresh(resolved: EntitlementState, expiration: Date?, graceEnd: Date?) {
        dueRefresh?.cancel()
        dueRefresh = nil
        let now = clock()
        let due = [resolved.tier == .premium ? expiration : nil, resolved == .premium(.grace) ? graceEnd : nil].compactMap { $0 }.filter { $0 > now }.min()
        guard let due else { return }
        // A week at most: a longer wait asks, finds nothing due, and waits again.
        let delay = min(due.timeIntervalSince(now) + 1, 7 * 86_400)
        dueRefresh = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// `remember`: write the tier for the next first frame (a DEBUG screenshot's fixed tier is not remembered).
    private func set(_ new: EntitlementState, remember: Bool = true) {
        let old = state.tier
        state = new
        if remember { cache.write(CachedTier(new)) }
        if new.tier != old { onTierChange?(new.tier, old) }
    }
}
