import Foundation

// The clock under the timed exercises (Breathing, Meditation; APP_RULES.md R33, R34). The same idea as
// the wind-down's: where a session is comes from the time since it began, less the time paused, never
// from counting ticks or frames, so a session that ran on behind the lock screen is exactly where it
// should be when the app comes back.

public struct SessionClock: Sendable, Equatable {
    public let plannedSeconds: TimeInterval
    public private(set) var startedAt: Date?
    public private(set) var pausedAt: Date?
    public private(set) var pausedTotal: TimeInterval = 0

    public init(seconds: TimeInterval) {
        plannedSeconds = max(seconds, 1)
    }

    public var hasStarted: Bool { startedAt != nil }
    public var isPaused: Bool { pausedAt != nil }

    public mutating func start(at now: Date) {
        startedAt = now
        pausedAt = nil
        pausedTotal = 0
    }

    public mutating func pause(at now: Date) {
        guard startedAt != nil, pausedAt == nil else { return }
        pausedAt = now
    }

    public mutating func resume(at now: Date) {
        guard let pausedAt else { return }
        pausedTotal += max(now.timeIntervalSince(pausedAt), 0)
        self.pausedAt = nil
    }

    /// Seconds of session that have passed: the time since the start, less the time paused.
    public func elapsed(at now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        let reference = pausedAt ?? now
        return min(max(reference.timeIntervalSince(startedAt) - pausedTotal, 0), plannedSeconds)
    }

    public func remaining(at now: Date) -> TimeInterval {
        plannedSeconds - elapsed(at: now)
    }

    public func isComplete(at now: Date) -> Bool {
        startedAt != nil && elapsed(at: now) >= plannedSeconds
    }

    /// How long to wait for the next whole second of the session (never less than a few
    /// milliseconds, so a wake a hair early does not spin).
    public func secondsToNextWholeSecond(at now: Date) -> TimeInterval {
        let elapsed = elapsed(at: now)
        return max(elapsed.rounded(.down) + 1 - elapsed, 0.005)
    }
}
