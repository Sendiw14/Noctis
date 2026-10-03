import Foundation
import NoctisCore
import UserNotifications

/// Takes a tap on one of NOCTIS's notifications to where it belongs. Their content stays
/// generic (R13); only the identifier decides (`NoctisNotification.route`): the evening
/// reminder opens Wind-down, without starting it.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let route = NoctisNotification.route(for: response.notification.request.identifier) else { return }
        await MainActor.run { model.open(route) }
    }
}
