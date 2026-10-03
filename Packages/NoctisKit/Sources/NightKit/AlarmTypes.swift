import Foundation

/// A day of the week, numbered as `Calendar` does: 1 is Sunday.
public enum AlarmWeekday: Int, CaseIterable, Sendable, Codable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public static func < (lhs: AlarmWeekday, rhs: AlarmWeekday) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Monday first, the order the repeat row shows.
    public static let mondayFirst: [AlarmWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    public static let weekdays: Set<AlarmWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    public static let weekend: Set<AlarmWeekday> = [.saturday, .sunday]
    public static let everyDay = Set(AlarmWeekday.allCases)
}

/// The alarm's life, as the person would put it. AlarmKit itself knows four states
/// (scheduled, countdown, paused, alerting); the rest are NOTICED here: a one-shot alarm that
/// has rung and been stopped is simply gone from the system, so "dismissed" is an alarm
/// that vanished (`AlarmService.reconcile`).
public enum AlarmState: String, Sendable, Codable, CaseIterable {
    /// Never scheduled, or scheduling was undone (the resting state).
    case off
    /// AlarmKit accepted it; the system hasn't listed it yet.
    case scheduled
    /// The system lists it, waiting for its time.
    case armed
    /// Rung, and the person chose Snooze: counting down to ring again.
    case snoozed
    /// Ringing now.
    case firing
    /// Rang and was stopped (a one-shot alarm is gone from the system after that).
    case dismissed
    /// The person turned it off.
    case cancelled
    /// The person said no (or turned alarms off in Settings).
    case permissionDenied
    /// This device can't schedule alarms.
    case unavailable
    /// Scheduling failed.
    case error

    /// A pending alarm: it will ring, or is ringing.
    public var isActive: Bool {
        switch self {
        case .scheduled, .armed, .snoozed, .firing: true
        case .off, .dismissed, .cancelled, .permissionDenied, .unavailable, .error: false
        }
    }
}

/// What the person can see and change about their wake alarm, and what is remembered of it
/// (`AlarmConfiguration` keeps one of these). It is the alarm's own record: the system
/// deletes a one-shot alarm the moment it has rung, so this is how we know it did.
public struct AlarmSettings: Sendable, Equatable, Codable {
    public static let snoozeChoices = [5, 9, 10]
    public static let defaultSnoozeMinutes = 9

    /// When it rings: minutes since midnight. Defaults to the profile's wake time.
    public var minutesSinceMidnight: Int
    /// The days it repeats; empty rings once.
    public var repeatDays: Set<AlarmWeekday>
    public var snoozeEnabled: Bool
    public var snoozeMinutes: Int
    /// The id AlarmKit knows it by, while it is scheduled.
    public var alarmKitID: UUID?
    public var lastState: AlarmState

    public init(
        minutesSinceMidnight: Int, repeatDays: Set<AlarmWeekday> = [], snoozeEnabled: Bool = false,
        snoozeMinutes: Int = AlarmSettings.defaultSnoozeMinutes, alarmKitID: UUID? = nil, lastState: AlarmState = .off
    ) {
        self.minutesSinceMidnight = BedtimeClock.wrap(minutesSinceMidnight)
        self.repeatDays = repeatDays
        self.snoozeEnabled = snoozeEnabled
        self.snoozeMinutes = AlarmSettings.snoozeChoices.contains(snoozeMinutes) ? snoozeMinutes : AlarmSettings.defaultSnoozeMinutes
        self.alarmKitID = alarmKitID
        self.lastState = lastState
    }

    /// The toggle: an alarm that is pending or ringing.
    public var isOn: Bool { lastState.isActive }

    /// What matters to the system when it rings: everything but the bookkeeping.
    public func sameAlarm(as other: AlarmSettings) -> Bool {
        minutesSinceMidnight == other.minutesSinceMidnight && repeatDays == other.repeatDays
            && snoozeEnabled == other.snoozeEnabled && snoozeMinutes == other.snoozeMinutes
    }
}

public enum AlarmAuthorization: String, Sendable, Codable, Equatable {
    /// Nobody has been asked yet: the first schedule (or `requestAuthorization`) asks.
    case notDetermined
    case denied
    case authorized
    /// This device can't schedule alarms.
    case unavailable
}

public enum AlarmFailure: String, Sendable, Codable, Equatable {
    /// AlarmKit's limit on scheduled alarms is reached.
    case limitReached
    case scheduleFailed
}

/// What the system tells us about one of our alarms.
public enum BackendAlarmState: Sendable, Equatable {
    case scheduled
    /// Counting down: a snoozed alarm.
    case countdown
    case paused
    case alerting
}

public struct BackendAlarm: Sendable, Equatable {
    public let id: UUID
    public let state: BackendAlarmState

    public init(id: UUID, state: BackendAlarmState) {
        self.id = id
        self.state = state
    }
}

public enum AlarmBackendError: Error, Equatable, Sendable {
    case limitReached
    case unavailable
    case failed
}

/// The alarm service's picture of the alarm: what to draw.
public struct AlarmStatus: Sendable, Equatable {
    public let settings: AlarmSettings
    public let state: AlarmState
    public let authorization: AlarmAuthorization
    public let failure: AlarmFailure?

    public init(settings: AlarmSettings, state: AlarmState, authorization: AlarmAuthorization, failure: AlarmFailure? = nil) {
        self.settings = settings
        self.state = state
        self.authorization = authorization
        self.failure = failure
    }

    public var isOn: Bool { state.isActive }
}
