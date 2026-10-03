import Foundation

/// The notifications NOCTIS schedules, by identifier, and where a tap on each goes.
/// Their content stays generic (APP_RULES.md R13): no streak, no score, no biometric value.
public nonisolated enum NoctisNotification {
    public static let morningSummary = "noctis.notification.morningSummary"
    public static let windDown = "noctis.notification.windDown"
    public static let weeklyReview = "noctis.notification.weeklyReview"

    /// Where a tap on the notification with `identifier` goes. The evening wind-down opens
    /// Wind-down without starting it (the person chose to open it, not to begin); the others
    /// just open the app.
    public static func route(for identifier: String) -> AppRoute? {
        switch identifier {
        case windDown: .windDown(autostart: false)
        default: nil
        }
    }
}
