import Foundation
import StoreKit

public enum StorePurchaseState: Equatable, Sendable {
    case idle
    case purchasing
    case pending
    case success
    case cancelled
    case failed(String)
}

public enum StoreLoadState: Equatable, Sendable {
    case loading
    case loaded
    case unavailable
}

/// The StoreKit 2 seam: loads real products, drives a purchase, listens
/// for out-of-band transaction updates (through `EntitlementManager`, which
/// listens), and keeps it in sync. Never fabricates a price or a product — every string the paywall
/// shows comes from a real `Product` once `products` loads.
@Observable
@MainActor
public final class StoreManager {
    public private(set) var products: [Product] = []
    public private(set) var loadState: StoreLoadState = .loading
    public var purchaseState: StorePurchaseState = .idle
    public let entitlementManager: EntitlementManager

    public init(entitlementManager: EntitlementManager = EntitlementManager()) {
        self.entitlementManager = entitlementManager
        // Renewals, refunds, Ask to Buy approvals and purchases made on another device reach the entitlement through its own listener.
        entitlementManager.startListening()
    }

    public var yearlyProduct: Product? { products.first { $0.id == StoreProductID.yearly } }
    public var monthlyProduct: Product? { products.first { $0.id == StoreProductID.monthly } }

    public func loadProducts() async {
        loadState = .loading
        guard let fetched = try? await Product.products(for: StoreProductID.all), !fetched.isEmpty else {
            products = []
            loadState = .unavailable
            return
        }
        products = fetched
        loadState = .loaded
        await entitlementManager.refresh()
    }

    /// True only when the subscription *group* itself has never been used
    /// — matches Apple's own semantics (intro eligibility is per-group,
    /// not per-product), so the yearly plan's "7 days free" badge and the
    /// monthly plan agree with each other.
    public func isEligibleForIntroOffer() async -> Bool {
        await Product.SubscriptionInfo.isEligibleForIntroOffer(for: StoreProductID.subscriptionGroupID)
    }

    public func purchase(_ product: Product) async {
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await entitlementManager.refresh()
                    purchaseState = .success
                case .unverified:
                    purchaseState = .failed("We couldn't verify this purchase.")
                }
            case .pending:
                purchaseState = .pending
            case .userCancelled:
                purchaseState = .cancelled
            @unknown default:
                purchaseState = .failed("Something went wrong. Please try again.")
            }
        } catch {
            purchaseState = .failed("Something went wrong. Please try again.")
        }
    }

    public enum RestoreResult: Equatable, Sendable {
        case restored
        case nothingFound
        case failed
    }

    public func restore() async -> RestoreResult {
        do {
            try await AppStore.sync()
        } catch {
            return .failed
        }
        await entitlementManager.refresh()
        return entitlementManager.hasAccess ? .restored : .nothingFound
    }
}
