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

    #if DEBUG
    private static var debugLoadScript: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-mockStoreLoad"), arguments.indices.contains(index + 1) else { return nil }
        let value = arguments[index + 1]
        return value == "loading" || value == "unavailable" ? value : nil
    }
    #endif

    public var yearlyProduct: Product? { products.first { $0.id == StoreProductID.yearly } }
    public var monthlyProduct: Product? { products.first { $0.id == StoreProductID.monthly } }

    public func loadProducts() async {
        loadState = .loading
        #if DEBUG
        // `-mockStoreLoad loading|unavailable`: the paywall in the state named, for a screenshot. The StoreKit configuration answers otherwise.
        if let script = Self.debugLoadScript {
            products = []
            if script == "unavailable" {
                loadState = .unavailable
            } else {
                try? await Task.sleep(for: .seconds(86_400))
            }
            return
        }
        #endif
        guard let fetched = try? await Product.products(for: StoreProductID.all), !fetched.isEmpty else {
            // A reload that fails keeps the plans already loaded: someone who opens the paywall again offline can still buy what they just saw.
            loadState = products.isEmpty ? .unavailable : .loaded
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
        #if DEBUG
        // QA part 6: `-introEligible yes|no` shows the paywall in each state on any device (StoreKit's answer is per simulator, from its own purchase history).
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-introEligible"), arguments.indices.contains(flag + 1) { return arguments[flag + 1] == "yes" }
        #endif
        return await Product.SubscriptionInfo.isEligibleForIntroOffer(for: StoreProductID.subscriptionGroupID)
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
