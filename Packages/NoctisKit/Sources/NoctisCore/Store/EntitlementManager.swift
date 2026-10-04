import Foundation
import StoreKit

/// Built from `Transaction.currentEntitlements` — by definition that
/// sequence only yields transactions the user is *currently* entitled to,
/// so renewal and expiry are handled implicitly (an expired subscription
/// simply stops appearing, no separate "is it expired" check needed).
/// Revocation behaves the same way: a revoked transaction is excluded.
/// Grace period is the one state that still counts as "entitled" here but
/// needs its own signal (from `Product.SubscriptionInfo.status`) since the
/// app should keep showing Premium content while billing retries.
@Observable
@MainActor
public final class EntitlementManager {
    public private(set) var hasActivePremium = false
    public private(set) var isInGracePeriod = false
    public private(set) var expirationDate: Date?
    public private(set) var willAutoRenew = true
    public private(set) var activeProductID: String?
    public private(set) var isInTrial = false
    #if DEBUG
    /// `-mockSubscription`: a fixed answer for a screenshot, since the simulator's StoreKit has no purchase.
    public private(set) var debugSummary: SubscriptionSummary?
    #endif

    public init() {}

    /// Grants Premium content the same as a normal active subscription —
    /// Apple's guidance is to keep serving entitled content through a
    /// billing grace period.
    public var hasAccess: Bool { hasActivePremium }

    /// What the Subscription page shows.
    public var summary: SubscriptionSummary {
        #if DEBUG
        if let debugSummary { return debugSummary }
        #endif
        return SubscriptionSummary(
            isPremium: hasActivePremium, plan: activeProductID.flatMap(SubscriptionSummary.Plan.init(productID:)), isTrial: isInTrial,
            willRenew: willAutoRenew, endDate: expirationDate, isInGracePeriod: isInGracePeriod
        )
    }

    #if DEBUG
    public func debugSet(_ summary: SubscriptionSummary) {
        debugSummary = summary
        hasActivePremium = summary.isPremium
    }
    #endif

    public func refresh() async {
        #if DEBUG
        if debugSummary != nil { return }
        #endif
        var accessGranted = false
        var latestExpiration: Date?
        var latestProduct: String?
        var trial = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard StoreProductID.all.contains(transaction.productID) else { continue }
            accessGranted = true
            // The newest period wins when more than one is current.
            if latestExpiration == nil || (transaction.expirationDate ?? .distantPast) >= (latestExpiration ?? .distantPast) {
                latestExpiration = transaction.expirationDate
                latestProduct = transaction.productID
                trial = transaction.offer?.type == .introductory && transaction.offer?.paymentMode == .freeTrial
            }
        }
        hasActivePremium = accessGranted
        expirationDate = latestExpiration
        activeProductID = latestProduct
        isInTrial = accessGranted && trial

        guard accessGranted,
              let products = try? await Product.products(for: StoreProductID.all),
              let subscription = products.first?.subscription else {
            isInGracePeriod = false
            return
        }
        let statuses = (try? await subscription.status) ?? []
        isInGracePeriod = statuses.contains { $0.state == .inGracePeriod }
        if let renewalInfo = statuses.first(where: { $0.state == .subscribed || $0.state == .inGracePeriod })?.renewalInfo,
           case .verified(let info) = renewalInfo {
            willAutoRenew = info.willAutoRenew
        }
    }
}
