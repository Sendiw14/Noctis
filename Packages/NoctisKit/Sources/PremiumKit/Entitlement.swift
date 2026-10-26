import Foundation

// What the person is entitled to (APP_RULES.md R57): worked out from what the App Store reports, as plain values, so every transition (a purchase, a
// trial, a grace period, a revocation, an expiry, a family-shared plan, an unverified answer) is a unit test against a fake client. Gating is presentation
// only: a lapsed subscription changes what is shown and nothing that is kept.

/// Where a Premium entitlement comes from.
public nonisolated enum PremiumSource: String, Sendable, Equatable, Codable {
    case purchased
    case trial
    /// Billing failed and the App Store is retrying: Premium continues until the grace period's own end.
    case grace
    case familySharing
}

public nonisolated enum EntitlementState: Sendable, Equatable {
    case free
    case premium(PremiumSource)
    /// Premium before, free now: the screens are the free ones, and everything the person recorded is still there.
    case previouslyPremiumNowFree

    public var tier: Tier {
        if case .premium = self { .premium } else { .free }
    }
}

/// The last tier NOCTIS saw, kept so the first frame is right before the App Store has answered (it is replaced by the answer every launch). "lapsed"
/// is "was Premium, is not now".
public nonisolated enum CachedTier: String, Sendable, Equatable {
    case free
    case premium
    case lapsed

    /// The state the first frame is drawn in.
    public var provisionalState: EntitlementState {
        switch self {
        case .free: .free
        case .premium: .premium(.purchased)
        case .lapsed: .previouslyPremiumNowFree
        }
    }

    public init(_ state: EntitlementState) {
        switch state {
        case .free: self = .free
        case .premium: self = .premium
        case .previouslyPremiumNowFree: self = .lapsed
        }
    }
}

public nonisolated enum Ownership: String, Sendable, Equatable {
    case purchased
    case familyShared
}

/// One current entitlement, as the App Store reports it (`Transaction`): only what the rules need.
public nonisolated struct EntitlementRecord: Sendable, Equatable {
    public var productID: String
    /// StoreKit's own verification of the signed transaction passed. An unverified one is ignored.
    public var isVerified: Bool
    public var revocationDate: Date?
    public var expirationDate: Date?
    public var ownership: Ownership
    public var isFreeTrial: Bool

    public init(
        productID: String, isVerified: Bool = true, revocationDate: Date? = nil, expirationDate: Date? = nil, ownership: Ownership = .purchased,
        isFreeTrial: Bool = false
    ) {
        self.productID = productID
        self.isVerified = isVerified
        self.revocationDate = revocationDate
        self.expirationDate = expirationDate
        self.ownership = ownership
        self.isFreeTrial = isFreeTrial
    }
}

/// The subscription's renewal state, for grace: `Product.SubscriptionInfo.Status` and its renewal info.
public nonisolated struct RenewalRecord: Sendable, Equatable {
    public enum State: String, Sendable, Equatable {
        case subscribed, expired, inBillingRetryPeriod, inGracePeriod, revoked, unknown
    }

    public var state: State
    public var isInBillingRetry: Bool
    /// When the grace period ends (`RenewalInfo.gracePeriodExpirationDate`); nil when there is none.
    public var gracePeriodExpirationDate: Date?
    public var willAutoRenew: Bool

    public init(state: State, isInBillingRetry: Bool = false, gracePeriodExpirationDate: Date? = nil, willAutoRenew: Bool = true) {
        self.state = state
        self.isInBillingRetry = isInBillingRetry
        self.gracePeriodExpirationDate = gracePeriodExpirationDate
        self.willAutoRenew = willAutoRenew
    }
}

public nonisolated enum EntitlementResolver {
    /// The state at `now`. Only verified transactions of `productIDs` count; a revoked one never does; an expired one does not, except while the grace period
    /// the App Store gave it (and its own end date) says Premium continues. Family-shared plans count as Premium. With nothing current, a person who was
    /// Premium (`previous`) is "previously Premium, now free".
    public static func resolve(
        records: [EntitlementRecord], renewal: RenewalRecord?, previous: CachedTier, productIDs: Set<String>, now: Date
    ) -> EntitlementState {
        let candidates = records.filter { $0.isVerified && productIDs.contains($0.productID) && $0.revocationDate == nil }
        let live = candidates.filter { ($0.expirationDate ?? .distantFuture) > now }
        if live.contains(where: { $0.ownership == .purchased && !$0.isFreeTrial }) { return .premium(.purchased) }
        if live.contains(where: { $0.ownership == .purchased && $0.isFreeTrial }) { return .premium(.trial) }
        if live.contains(where: { $0.ownership == .familyShared }) { return .premium(.familySharing) }
        // Grace: the entitlement has run out by its own date, but billing is being retried and the App Store has said when that stops.
        if !candidates.isEmpty, let renewal, renewal.state == .inGracePeriod || renewal.state == .inBillingRetryPeriod || renewal.isInBillingRetry,
            let graceEnd = renewal.gracePeriodExpirationDate, graceEnd > now
        {
            return .premium(.grace)
        }
        switch previous {
        case .premium, .lapsed: return .previouslyPremiumNowFree
        case .free: return .free
        }
    }
}
