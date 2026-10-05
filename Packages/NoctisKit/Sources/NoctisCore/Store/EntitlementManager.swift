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
    /// Told when the tier changes: the new tier and the old.
    @ObservationIgnored public var onTierChange: (@MainActor (_ new: Tier, _ old: Tier) -> Void)?

    public init(client: any EntitlementClient = StoreKitEntitlementClient(), cache: EntitlementCache = EntitlementCache(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.cache = cache
        self.clock = clock
        state = cache.read().provisionalState
    }

    public var tier: Tier { state.tier }
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
            endDate: expirationDate, isInGracePeriod: isInGracePeriod, isFamilyShared: isFamilyShared, hasLapsed: state == .previouslyPremiumNowFree
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
        let records = await client.records()
        let renewal = await client.renewal()
        let resolved = EntitlementResolver.resolve(
            records: records, renewal: renewal, previous: cache.read(), productIDs: Set(StoreProductID.all), now: clock()
        )
        // The newest period wins when more than one is current.
        let valid = records.filter { $0.isVerified && $0.revocationDate == nil && StoreProductID.all.contains($0.productID) }
        let newest = valid.max { ($0.expirationDate ?? .distantPast) < ($1.expirationDate ?? .distantPast) }
        expirationDate = resolved.tier == .premium ? newest?.expirationDate : nil
        activeProductID = resolved.tier == .premium ? newest?.productID : nil
        willAutoRenew = renewal?.willAutoRenew ?? true
        isResolved = true
        set(resolved)
    }

    /// `remember`: write the tier for the next first frame (a DEBUG screenshot's fixed tier is not remembered).
    private func set(_ new: EntitlementState, remember: Bool = true) {
        let old = state.tier
        state = new
        if remember { cache.write(CachedTier(new)) }
        if new.tier != old { onTierChange?(new.tier, old) }
    }
}
