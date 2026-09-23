import Foundation

/// Product/group identifiers must match `Noctis.storekit` exactly — the
/// subscription group id here is the same string used in that file's
/// `subscriptionGroups[0].id`, which is what
/// `Product.SubscriptionInfo.isEligibleForIntroOffer(for:)` keys off of.
public enum StoreProductID {
    public static let yearly = "com.noctis.app.premium.yearly"
    public static let monthly = "com.noctis.app.premium.monthly"
    public static let all = [yearly, monthly]
    public static let subscriptionGroupID = "A9FA6F3F-A632-4D06-84D7-9BBEC7879C99"
}

/// Placeholder legal URLs — swap for the real published pages before
/// shipping. Centralized so the paywall footer never hardcodes a URL
/// inline.
public enum StoreLegalLinks {
    public static let terms = URL(string: "https://noctis.app/terms")!
    public static let privacy = URL(string: "https://noctis.app/privacy")!
}
