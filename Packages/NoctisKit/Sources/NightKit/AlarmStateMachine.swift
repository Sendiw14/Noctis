import Foundation

/// Things that happen to the alarm.
public enum AlarmEvent: Sendable, Equatable, CaseIterable {
    /// The person said no, or switched alarms off in Settings.
    case authorizationDenied
    /// Alarms were allowed again (the prompt, or Settings).
    case authorizationGranted
    /// This device can't schedule alarms.
    case alarmsUnavailable
    /// AlarmKit accepted a schedule request.
    case scheduleAccepted
    /// AlarmKit refused one.
    case scheduleFailed
    /// The system lists the alarm, waiting for its time.
    case systemScheduled
    /// The system lists the alarm counting down: it was snoozed.
    case systemCountdown
    /// The system lists the alarm ringing.
    case systemAlerting
    /// The system no longer lists the alarm: it rang and was stopped.
    case systemGone
    /// The person turned the alarm off.
    case cancelRequested
    /// The person chose to try again.
    case reset
}

/// The alarm's state transitions, as one pure function (APP_RULES.md R30). Every transition
/// that exists is listed; every other pair is ignored and leaves the state as it was, so a
/// late or repeated report from the system can't put the alarm somewhere it never was.
public enum AlarmStateMachine {
    public struct Transition: Equatable, Sendable {
        public let state: AlarmState
        public let changed: Bool
    }

    public static func reduce(_ state: AlarmState, _ event: AlarmEvent) -> Transition {
        guard let next = next(state, event), next != state else { return Transition(state: state, changed: false) }
        return Transition(state: next, changed: true)
    }

    /// The state `event` leads to, or nil when it means nothing in `state`.
    static func next(_ state: AlarmState, _ event: AlarmEvent) -> AlarmState? {
        // Permission and availability can be lost in any state, and a refused schedule is an
        // error in any state that was trying to schedule.
        switch event {
        case .authorizationDenied: return state == .permissionDenied || state == .unavailable ? nil : .permissionDenied
        case .alarmsUnavailable: return .unavailable
        default: break
        }
        switch (state, event) {
        // Off, and the resting states that follow a finished or cancelled alarm.
        case (.off, .scheduleAccepted), (.dismissed, .scheduleAccepted), (.cancelled, .scheduleAccepted), (.error, .scheduleAccepted):
            return .scheduled
        case (.off, .scheduleFailed), (.dismissed, .scheduleFailed), (.cancelled, .scheduleFailed), (.error, .scheduleFailed):
            return .error
        case (.error, .reset), (.permissionDenied, .reset), (.unavailable, .reset):
            return .off
        case (.permissionDenied, .authorizationGranted):
            return .off
        case (.error, .cancelRequested):
            return .cancelled

        // Waiting to ring.
        case (.scheduled, .systemScheduled):
            return .armed
        case (.scheduled, .scheduleAccepted), (.armed, .scheduleAccepted), (.snoozed, .scheduleAccepted), (.firing, .scheduleAccepted):
            // An update re-schedules it: pending again until the system lists it.
            return .scheduled
        case (.scheduled, .scheduleFailed), (.armed, .scheduleFailed), (.snoozed, .scheduleFailed), (.firing, .scheduleFailed):
            return .error
        case (.scheduled, .systemAlerting), (.armed, .systemAlerting), (.snoozed, .systemAlerting):
            return .firing
        case (.scheduled, .systemCountdown), (.armed, .systemCountdown), (.firing, .systemCountdown):
            return .snoozed
        case (.snoozed, .systemScheduled), (.firing, .systemScheduled):
            // Stopped, and it repeats: waiting for the next day.
            return .armed
        case (.scheduled, .systemGone), (.armed, .systemGone), (.snoozed, .systemGone), (.firing, .systemGone):
            return .dismissed
        case (.scheduled, .cancelRequested), (.armed, .cancelRequested), (.snoozed, .cancelRequested), (.firing, .cancelRequested):
            return .cancelled
        default:
            return nil
        }
    }
}
