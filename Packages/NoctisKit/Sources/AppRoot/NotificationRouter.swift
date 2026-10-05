import Foundation
import NoctisCore
import UserNotifications

/// Takes a tap on one of NOCTIS's notifications to where it belongs. Their content stays
/// generic (R13); only the identifier and the plan decide (`NoctisNotification.route`): the evening
/// reminder opens Wind-down, without starting it, for Premium, and Tonight for the free plan.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        await MainActor.run {
            // Premium's evening reminder opens the wind-down; the free plan's opens Tonight (R61).
            guard let route = NoctisNotification.route(for: identifier, tier: model.tier) else { return }
            model.open(route)
        }
    }
}
