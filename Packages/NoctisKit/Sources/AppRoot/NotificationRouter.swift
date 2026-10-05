import Foundation
import NoctisCore
import UserNotifications

/// Takes a tap on one of NOCTIS's notifications to where it belongs. Their content stays
/// generic (R13); only the identifier and the plan decide (`NoctisNotification.route`): the evening
/// reminder opens Wind-down, without starting it, for Premium, and Tonight for the free plan; the weekly reminder opens the latest weekly review.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        await MainActor.run { handle(identifier: identifier) }
    }

    /// What a tap on the notification with `identifier` does: Premium's evening reminder opens the wind-down and the free plan's opens Tonight (R61); the weekly one opens the
    /// latest weekly review (R63). The delegate calls this and so does the DEBUG tap (`-noctisNotificationTap <identifier>`).
    @MainActor
    func handle(identifier: String) {
        guard let route = NoctisNotification.route(for: identifier, tier: model.tier) else { return }
        model.open(route)
    }
}
