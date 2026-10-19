import Foundation

/// Product/group identifiers must match `Noctis.storekit` exactly — the
/// subscription group id here is the same string used in that file's
/// `subscriptionGroups[0].id`, which is what
/// `Product.SubscriptionInfo.isEligibleForIntroOffer(for:)` keys off of.
public nonisolated enum StoreProductID {
    public static let yearly = "com.noctis.app.premium.yearly"
    public static let monthly = "com.noctis.app.premium.monthly"
    public static let all = [yearly, monthly]
    public static let subscriptionGroupID = "A9FA6F3F-A632-4D06-84D7-9BBEC7879C99"
}

/// Placeholder legal URLs — swap for the real published pages before
/// shipping. Centralized so the paywall footer never hardcodes a URL
/// inline.
public nonisolated enum StoreLegalLinks {
    public static let terms = URL(string: "https://noctis.app/terms")!
    public static let privacy = URL(string: "https://noctis.app/privacy")!
    /// Apple's standard licensed-application agreement: the Terms the Welcome screen and the subscription refer to.
    public static let appleStandardTerms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") ?? terms
    /// Where "Contact support" writes to. Placeholder like the two links above: swap for the real inbox before
    /// shipping (ROADMAP.md).
    public static let supportEmail = "support@noctis.app"
}
