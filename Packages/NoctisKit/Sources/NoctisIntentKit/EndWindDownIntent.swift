import ActivityKit
import AppIntents
import Foundation
import NoctisWidgetKit

// The wind-down Live Activity's End button (APP_RULES.md R49). The button is drawn by the extension, but the session is the app's: this is a
// `LiveActivityIntent`, so iOS runs it in the app's own process (starting the app in the background if it has to), where it ends the session
// the way the End button on the wind-down screen does, and then makes sure no activity is left, whatever the app did or did not know.

/// The wind-down Live Activities the system holds for NOCTIS: the one doorway to ActivityKit for them. An activity is told apart by its id, and
/// never leaves this file, so nothing crosses an isolation boundary.
public enum WindDownActivities {
    public typealias Content = ActivityContent<WindDownActivityAttributes.ContentState>

    /// Whether the person allows Live Activities (Settings, or the app's own switch).
    public static var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Starts one, from the foreground; its id. Throws where the system says no (too many activities, not in the foreground).
    public static func request(_ attributes: WindDownActivityAttributes, content: Content) throws -> String {
        try Activity.request(attributes: attributes, content: content, pushType: nil).id
    }

    public static func update(id: String, content: Content) async {
        await Activity<WindDownActivityAttributes>.activities.first { $0.id == id }?.update(content)
    }

    public static func end(id: String, content: Content?, dismissal: ActivityUIDismissalPolicy) async {
        await Activity<WindDownActivityAttributes>.activities.first { $0.id == id }?.end(content, dismissalPolicy: dismissal)
    }

    /// Ends them all at once. Used by the End button, by the clean-up when the app starts, and by "Delete all NOCTIS data".
    public static func endAll() async {
        for activity in Activity<WindDownActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

/// Ends the wind-down from the Lock Screen or the Dynamic Island. Not in the Shortcuts gallery: it is a button on the activity, not an action.
public struct EndWindDownIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "End wind-down"
    public static let description = IntentDescription("Ends the wind-down that is running.", categoryName: "Sleep")
    public static let isDiscoverable = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        let runtime = IntentRuntime.current
        // The app's session first: it fades the sound, lets the screen sleep again and remembers that it ended early.
        if let host = await runtime.host() { host.endWindDown() }
        // Then whatever is left. The person pressed End: nothing may stay on their Lock Screen.
        await runtime.environment.endWindDownActivities()
        return .result()
    }
}
