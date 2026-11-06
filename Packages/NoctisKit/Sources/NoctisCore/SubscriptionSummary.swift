import Foundation

/// What the Subscription page says, as plain values: Free or Premium, which plan, whether it is a free trial,
/// when it renews or ends. Built by `EntitlementManager` from the store; pure here so every sentence is tested.
public nonisolated struct SubscriptionSummary: Sendable, Equatable {
    public enum Plan: String, Sendable, Equatable {
        case monthly, yearly

        public init?(productID: String) {
            switch productID {
            case StoreProductID.monthly: self = .monthly
            case StoreProductID.yearly: self = .yearly
            default: return nil
            }
        }

        public var name: String { self == .monthly ? "Monthly" : "Yearly" }
    }

    public var isPremium: Bool
    public var plan: Plan?
    /// The current period is an introductory free trial.
    public var isTrial: Bool
    public var willRenew: Bool
    /// When the current period ends (and, if it renews, when it does).
    public var endDate: Date?
    /// Billing failed and the store is retrying: Premium continues for now.
    public var isInGracePeriod: Bool
    /// Premium comes through Family Sharing, from the person who bought it.
    public var isFamilyShared: Bool
    /// Premium before, free now: everything NOCTIS recorded is still here.
    public var hasLapsed: Bool
    /// Billing failed, the App Store is still retrying and there is no grace period: Premium is paused until the payment goes through (S1B-C03).
    public var hasPaymentProblem: Bool

    public init(
        isPremium: Bool = false, plan: Plan? = nil, isTrial: Bool = false, willRenew: Bool = true, endDate: Date? = nil, isInGracePeriod: Bool = false,
        isFamilyShared: Bool = false, hasLapsed: Bool = false, hasPaymentProblem: Bool = false
    ) {
        self.isPremium = isPremium
        self.plan = plan
        self.isTrial = isTrial
        self.willRenew = willRenew
        self.endDate = endDate
        self.isInGracePeriod = isInGracePeriod
        self.isFamilyShared = isFamilyShared
        self.hasLapsed = hasLapsed
        self.hasPaymentProblem = hasPaymentProblem && !isPremium
    }

    public static let free = SubscriptionSummary()

    /// "Free", or "Premium".
    public var title: String { isPremium ? "Premium" : "Free" }

    /// The line under the page's title: what the plan is, in a few words (S1B-R-11: a paused plan is not called the free plan).
    public var pageSummary: String {
        isPremium ? "You have Premium." : (hasPaymentProblem ? "Your payment needs attention." : "You're on the free plan.")
    }

    /// "Premium · Yearly" on the row of the Subscription page.
    public var headline: String {
        guard isPremium else { return hasPaymentProblem ? "Premium paused" : "Free" }
        return plan.map { "Premium · \($0.name)" } ?? "Premium"
    }

    /// The one line under the headline. Nothing about price: the store, not NOCTIS, knows what was charged.
    public func detail(calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) -> String {
        guard isPremium else {
            if hasPaymentProblem {
                return "Your last payment didn't go through, so Premium is paused. Check your payment method in Manage subscription and it comes back once the App Store can charge it. Everything NOCTIS recorded for you is still here."
            }
            return hasLapsed
                ? "Your Premium has ended. Everything NOCTIS recorded for you is still here, and you can upgrade again at any time."
                : "You can upgrade to Premium at any time."
        }
        if isFamilyShared { return "Premium is shared with you through Family Sharing." }
        let date = endDate.map {
            $0.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day().year())
        }
        if isInGracePeriod {
            return "Your last payment didn't go through. Premium continues while the App Store tries again; check your payment method in Manage subscription."
        }
        if isTrial {
            guard let date else { return "You're in your free trial." }
            return willRenew ? "Your free trial ends on \(date), then it renews." : "Your free trial ends on \(date). It won't renew."
        }
        guard let date else { return "Premium is active." }
        return willRenew ? "Renews on \(date)." : "Ends on \(date). It won't renew."
    }
}
