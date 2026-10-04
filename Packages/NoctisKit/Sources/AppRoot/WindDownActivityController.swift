import ActivityKit
import Foundation
import NightFeature
import NoctisIntentKit
import NoctisWidgetKit

/// The one doorway to ActivityKit for the wind-down (APP_RULES.md R49), so the controller's own logic (what is asked when, and that a refusal is
/// silent) is a unit test against a fake and only this thin layer touches the system.
@MainActor
protocol WindDownActivityClient: AnyObject {
    /// Whether the person allows Live Activities (Settings, Face ID & Passcode, or the app's own switch).
    var isEnabled: Bool { get }
    /// Starts one; the id it can be told apart by. Throws where the system says no (too many activities, not in the foreground).
    func request(_ attributes: WindDownActivityAttributes, content: ActivityContent<WindDownActivityAttributes.ContentState>) throws -> String
    func update(_ id: String, content: ActivityContent<WindDownActivityAttributes.ContentState>) async
    func end(_ id: String, content: ActivityContent<WindDownActivityAttributes.ContentState>?, dismissal: ActivityUIDismissalPolicy) async
    /// Ends every wind-down activity there is, whatever started it (an earlier run of the app, the End button).
    func endAll() async
}

/// Starts, updates and ends the wind-down's Live Activity as the session asks. One activity at a time. Where Live Activities are off, or the
/// system refuses one, nothing is shown and nothing is said: the wind-down goes on as it always did.
@MainActor
final class WindDownActivityController: WindDownActivityHosting {
    private let client: any WindDownActivityClient
    private var id: String?
    /// What is asked of the system happens in the order it was asked.
    private var tail: Task<Void, Never>?

    init(client: any WindDownActivityClient) {
        self.client = client
    }

    func start(_ attributes: WindDownActivityAttributes, state: WindDownActivityAttributes.ContentState) {
        guard client.isEnabled else { return }
        let client = client
        enqueue { [self] in
            // One session, one activity: anything a run the system ended left behind goes first.
            await client.endAll()
            do {
                id = try client.request(attributes, content: Self.content(state))
            } catch {
                id = nil
            }
        }
    }

    func update(_ state: WindDownActivityAttributes.ContentState) {
        let client = client
        enqueue { [self] in
            guard let id else { return }
            await client.update(id, content: Self.content(state))
        }
    }

    func end(finalState: WindDownActivityAttributes.ContentState?, dismissAfter: TimeInterval) {
        let client = client
        enqueue { [self] in
            guard let id else { return }
            self.id = nil
            if let finalState {
                await client.end(id, content: ActivityContent(state: finalState, staleDate: nil), dismissal: .after(Date().addingTimeInterval(dismissAfter)))
            } else {
                await client.end(id, content: nil, dismissal: .immediate)
            }
        }
    }

    /// A Live Activity an earlier run of the app left behind (the system ended it, or the person did, while NOCTIS was not running): ended when
    /// the app starts, in the same order as everything else asked of the system, so it can never end the session that starts right after.
    func endLeftovers() {
        let client = client
        enqueue { await client.endAll() }
    }

    /// What the system shows is stale from the moment the time runs out, so a session that ended while the app was away says "Wind-down complete"
    /// instead of a clock stuck at 0:00.
    static func content(_ state: WindDownActivityAttributes.ContentState) -> ActivityContent<WindDownActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: WindDownActivityState.staleDate(for: state))
    }

    /// Everything asked so far has been done (a test waits on it).
    func settled() async {
        await tail?.value
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
}

/// The system's ActivityKit, as the controller asks for it (through `WindDownActivities`, which holds the activities).
@MainActor
final class ActivityKitWindDownClient: WindDownActivityClient {
    var isEnabled: Bool { WindDownActivities.isEnabled }

    func request(_ attributes: WindDownActivityAttributes, content: ActivityContent<WindDownActivityAttributes.ContentState>) throws -> String {
        try WindDownActivities.request(attributes, content: content)
    }

    func update(_ id: String, content: ActivityContent<WindDownActivityAttributes.ContentState>) async {
        await WindDownActivities.update(id: id, content: content)
    }

    func end(_ id: String, content: ActivityContent<WindDownActivityAttributes.ContentState>?, dismissal: ActivityUIDismissalPolicy) async {
        await WindDownActivities.end(id: id, content: content, dismissal: dismissal)
    }

    func endAll() async {
        await WindDownActivities.endAll()
    }
}
