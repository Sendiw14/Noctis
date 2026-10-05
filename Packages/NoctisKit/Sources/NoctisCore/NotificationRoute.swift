import Foundation
import PremiumKit

/// The notifications NOCTIS schedules, by identifier, and where a tap on each goes.
/// Their content stays generic (APP_RULES.md R13): no streak, no score, no biometric value.
public nonisolated enum NoctisNotification {
    public static let morningSummary = "noctis.notification.morningSummary"
    public static let windDown = "noctis.notification.windDown"
    public static let weeklyReview = "noctis.notification.weeklyReview"

    /// Where a tap on the notification with `identifier` goes. For Premium the evening reminder opens Wind-down without starting it (the person chose
    /// to open it, not to begin); the free plan has no session, so it opens Tonight (APP_RULES.md R61). The weekly one opens the latest weekly review, whose cover
    /// is free (R63); its text stays as generic as it was. The morning one just opens the app.
    public static func route(for identifier: String, tier: Tier) -> AppRoute? {
        switch identifier {
        case windDown: tier == .premium ? .windDown(autostart: false) : .tonight
        case weeklyReview: .review(kind: .weekly)
        default: nil
        }
    }
}
