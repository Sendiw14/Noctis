import Foundation
import NoctisWidgetKit

/// What the wind-down asks of its Live Activity (APP_RULES.md R49). The session owns the clock; this only shows it. A real host starts the
/// activity (silently doing nothing where Live Activities are off), and a fake in the tests says what was asked.
@MainActor
public protocol WindDownActivityHosting: AnyObject {
    /// The session began. Asked once per session, in the foreground, which is where an activity may be started.
    func start(_ attributes: WindDownActivityAttributes, state: WindDownActivityAttributes.ContentState)
    /// Paused or resumed: the same session, with the window as it is now.
    func update(_ state: WindDownActivityAttributes.ContentState)
    /// The session is over. With a `finalState` the activity shows it for `dismissAfter` seconds (the time ran out: "Wind-down complete");
    /// without one it goes at once (the person ended it, or everything was deleted).
    func end(finalState: WindDownActivityAttributes.ContentState?, dismissAfter: TimeInterval)
}
