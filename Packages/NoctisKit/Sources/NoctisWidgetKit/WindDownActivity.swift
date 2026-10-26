#if os(iOS)
import ActivityKit
import Foundation
import NoctisText

// The wind-down's Live Activity (APP_RULES.md R49): what it holds, and what it says. Pure data and pure words, so every state is a unit
// test, the extension draws it and the app (and the debug gallery) can draw the very same views.

/// A wind-down session on the Lock Screen and in the Dynamic Island. What never changes in a session is the attributes; what does is the
/// content state: running, paused or ending, and the window of time it counts through.
public nonisolated struct WindDownActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Phase: String, Codable, Hashable, Sendable {
            case running
            case paused
            /// Over: the time ran out, a moment before the Live Activity goes.
            case ending
        }

        public var phase: Phase
        /// The window the countdown runs through. A pause moves both ends on by the time spent paused, so one start and one end say how
        /// much is left at any moment, whether the app is awake or not.
        public var windowStart: Date
        public var windowEnd: Date
        /// When it was paused, while it is: the countdown stands still there.
        public var pausedAt: Date?

        public init(phase: Phase, windowStart: Date, windowEnd: Date, pausedAt: Date? = nil) {
            self.phase = phase
            self.windowStart = windowStart
            self.windowEnd = max(windowEnd, windowStart)
            self.pausedAt = pausedAt
        }

        /// The moment the countdown reads at `date`: frozen while paused.
        public func reading(at date: Date) -> Date { min(max(pausedAt ?? date, windowStart), windowEnd) }

        /// Seconds left at `date`, never negative.
        public func remaining(at date: Date) -> TimeInterval { windowEnd.timeIntervalSince(reading(at: date)) }

        /// 0 at the start, 1 at the end.
        public func progress(at date: Date) -> Double {
            let total = windowEnd.timeIntervalSince(windowStart)
            guard total > 0 else { return 1 }
            return min(max(reading(at: date).timeIntervalSince(windowStart) / total, 0), 1)
        }

        public var isPaused: Bool { phase == .paused }
    }

    /// The length the person chose (10, 20 or 30).
    public var plannedMinutes: Int
    /// When it began.
    public var startedAt: Date

    public init(plannedMinutes: Int, startedAt: Date) {
        self.plannedMinutes = plannedMinutes
        self.startedAt = startedAt
    }
}

/// Makes the content state from the numbers a session's clock holds, so the app never works the window out in two places.
public nonisolated enum WindDownActivityState {
    /// `startedAt` and `pausedTotal` are the clock's: the window starts when the session began, less what was spent paused.
    public static func make(
        phase: WindDownActivityAttributes.ContentState.Phase, startedAt: Date, pausedTotal: TimeInterval, plannedSeconds: TimeInterval, pausedAt: Date? = nil
    ) -> WindDownActivityAttributes.ContentState {
        let start = startedAt.addingTimeInterval(pausedTotal)
        return WindDownActivityAttributes.ContentState(
            phase: phase, windowStart: start, windowEnd: start.addingTimeInterval(plannedSeconds), pausedAt: phase == .paused ? pausedAt : nil)
    }

    /// The system marks the activity stale at this moment, so a session that ran out while the app was away says so instead of "0:00".
    public static func staleDate(for state: WindDownActivityAttributes.ContentState) -> Date? {
        state.phase == .running ? state.windowEnd : nil
    }
}

/// The words on every presentation (a test holds all of them to the banned-language list).
public nonisolated enum WindDownActivityCopy {
    public static let title = "Wind down"
    public static let paused = "Paused"
    public static let complete = "Wind-down complete"
    public static let end = "End"
    public static let endAccessibility = "End wind-down"

    /// "20 min", under the title while it runs.
    public static func length(_ minutes: Int) -> String { "\(minutes) min" }

    /// What the second line says in `state`; `isStale` is the system's own flag that the time has run out with the app away.
    public static func status(_ state: WindDownActivityAttributes.ContentState, plannedMinutes: Int, isStale: Bool) -> String {
        if state.phase == .ending || isStale { return complete }
        if state.phase == .paused { return paused }
        return length(plannedMinutes)
    }

    /// One sentence for a screen reader, for a presentation that is not a live timer (the gallery, a test): "Wind down. 12 minutes left."
    public static func spoken(_ state: WindDownActivityAttributes.ContentState, at date: Date, isStale: Bool = false) -> String {
        if state.phase == .ending || isStale { return "\(title). \(complete)." }
        let minutes = Int((state.remaining(at: date) / 60).rounded(.up))
        let left = NoctisCount.minutesLeft(minutes)
        return state.isPaused ? "\(title). \(paused). \(left)." : "\(title). \(left)."
    }
}
#endif
