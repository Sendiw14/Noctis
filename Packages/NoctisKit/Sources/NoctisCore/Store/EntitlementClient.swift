import Foundation
import PremiumKit
import StoreKit

/// What `EntitlementManager` asks the store: the current entitlements, the renewal state (for grace), and when either may have changed. The real one is
/// StoreKit 2; tests use a fake that answers by hand (APP_RULES.md R57).
public protocol EntitlementClient: Sendable {
    func records() async -> [EntitlementRecord]
    func renewal() async -> RenewalRecord?
    /// A value each time a transaction arrives or changes (a renewal, a refund, a purchase made on another device, an Ask to Buy approval).
    func updates() -> AsyncStream<Void>
}

/// StoreKit 2. `Transaction.currentEntitlements` yields the latest transaction of each product the person is entitled to (verified or not: an unverified
/// one is passed on marked, and ignored by the rules); `Product.SubscriptionInfo.Status` and its renewal info give the billing state and the grace period's
/// end. Local only: StoreKit keeps the signed transactions on the device, so this works with no connection.
public struct StoreKitEntitlementClient: EntitlementClient {
    public init() {}

    public func records() async -> [EntitlementRecord] {
        var found: [EntitlementRecord] = []
        for await result in Transaction.currentEntitlements {
            let (transaction, verified): (Transaction, Bool)
            switch result {
            case .verified(let value): (transaction, verified) = (value, true)
            case .unverified(let value, _): (transaction, verified) = (value, false)
            }
            found.append(
                EntitlementRecord(
                    productID: transaction.productID, isVerified: verified, revocationDate: transaction.revocationDate,
                    expirationDate: transaction.expirationDate,
                    ownership: transaction.ownershipType == .familyShared ? .familyShared : .purchased,
                    isFreeTrial: transaction.offer?.type == .introductory && transaction.offer?.paymentMode == .freeTrial
                )
            )
        }
        return found
    }

    public func renewal() async -> RenewalRecord? {
        guard let products = try? await Product.products(for: StoreProductID.all), let subscription = products.first?.subscription,
            let statuses = try? await subscription.status, !statuses.isEmpty
        else { return nil }
        // The status that says the most: one in grace or billing retry first, then a subscribed one.
        let status =
            statuses.first { $0.state == .inGracePeriod || $0.state == .inBillingRetryPeriod } ?? statuses.first { $0.state == .subscribed } ?? statuses[0]
        let state: RenewalRecord.State
        switch status.state {
        case .subscribed: state = .subscribed
        case .expired: state = .expired
        case .inBillingRetryPeriod: state = .inBillingRetryPeriod
        case .inGracePeriod: state = .inGracePeriod
        case .revoked: state = .revoked
        default: state = .unknown
        }
        guard case .verified(let info) = status.renewalInfo else { return RenewalRecord(state: state) }
        return RenewalRecord(
            state: state, isInBillingRetry: info.isInBillingRetry, gracePeriodExpirationDate: info.gracePeriodExpirationDate, willAutoRenew: info.willAutoRenew)
    }

    public func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await update in Transaction.updates {
                    if case .verified(let transaction) = update { await transaction.finish() }
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
