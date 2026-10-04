import Foundation
import NoctisIntentKit

/// The Live Activities NOCTIS has started (APP_RULES.md R49): the wind-down's. The wake alarm's snooze countdown is AlarmKit's, and it ends
/// when the alarm is cancelled (the delete-all step before this one). This is the one place "Delete all NOCTIS data" ends them, so none can be
/// left running.
enum LiveActivities {
    @MainActor
    static func endAll() async {
        await WindDownActivities.endAll()
    }
}
