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

    public init() {}

    /// Grants Premium content the same as a normal active subscription —
    /// Apple's guidance is to keep serving entitled content through a
    /// billing grace period.
    public var hasAccess: Bool { hasActivePremium }

    public func refresh() async {
        var accessGranted = false
        var latestExpiration: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard StoreProductID.all.contains(transaction.productID) else { continue }
            accessGranted = true
            latestExpiration = transaction.expirationDate
        }
        hasActivePremium = accessGranted
        expirationDate = latestExpiration

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
