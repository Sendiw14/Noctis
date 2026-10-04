import Foundation

// The wind-down session's engine (APP_RULES.md R32): a clock, a state machine and the numbers the
// scene is drawn from. Pure and deterministic: progress comes from the clock, never from counting
// frames or ticks, so a session that ran on behind the lock screen is exactly where it should be.

public enum WindDownState: Sendable, Equatable, CaseIterable {
    /// Not begun: the duration, the sound and "Begin".
    case idle
    case running
    case paused
    /// Over: the sound is fading, a soft haptic has been given; the finish card is a moment away.
    case ending
    case finished
}

public enum WindDownEvent: Sendable, Equatable, CaseIterable {
    case begin
    case pause
    case resume
    /// The planned time has run out.
    case reachedEnd
    /// The person ended it.
    case endEarly
    /// The ending's fade is done.
    case endingDone
    /// Back to the start (after the finish card).
    case reset
}

public enum WindDownMachine {
    /// The state `event` leads to, or `state` itself when it means nothing there.
    public static func reduce(_ state: WindDownState, _ event: WindDownEvent) -> WindDownState {
        switch (state, event) {
        case (.idle, .begin): .running
        case (.running, .pause): .paused
        case (.paused, .resume): .running
        case (.running, .reachedEnd), (.paused, .reachedEnd): .ending
        case (.running, .endEarly), (.paused, .endEarly): .ending
        case (.ending, .endingDone): .finished
        case (.finished, .reset), (.ending, .reset), (.running, .reset), (.paused, .reset): .idle
        default: state
        }
    }
}

/// How long a session is, and where it is in that time.
public struct WindDownClock: Sendable, Equatable {
    public static let options = [10, 20, 30]
    public static let defaultMinutes = 20

    public let plannedSeconds: TimeInterval
    public private(set) var startedAt: Date?
    public private(set) var pausedAt: Date?
    public private(set) var pausedTotal: TimeInterval = 0

    public init(minutes: Int) {
        plannedSeconds = TimeInterval(max(minutes, 1) * 60)
    }

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

    /// 0 at the start, 1 at the end.
    public func progress(at now: Date) -> Double {
        elapsed(at: now) / plannedSeconds
    }

    public func remaining(at now: Date) -> TimeInterval {
        plannedSeconds - elapsed(at: now)
    }

    public func isComplete(at now: Date) -> Bool {
        startedAt != nil && elapsed(at: now) >= plannedSeconds
    }
}

/// How much of the screen is left as the session goes on: the product gets quieter.
public enum WindDownStage: Sendable, Equatable, CaseIterable {
    /// Before the simplify point: the action row, and labelled controls.
    case full
    /// Past it: the controls shrink to icons and the action row goes.
    case reduced
    /// From 60%: only a small End and the sound toggle.
    case minimal

    public static let simplifyPoint = 0.3
    public static let minimalPoint = 0.6

    public static func stage(for progress: Double) -> WindDownStage {
        if progress >= minimalPoint { return .minimal }
        if progress >= simplifyPoint { return .reduced }
        return .full
    }

    /// Animation durations lengthen as the session goes on: a change late in the session is slow.
    public static func transitionSeconds(for progress: Double) -> Double {
        0.35 + 1.2 * min(max(progress, 0), 1)
    }
}

/// The scene as numbers: everything that moves is a function of progress `p` (0...1), so a test
/// can check it and the drawing only maps it.
public enum WindDownVisuals {
    public static let starsAtStart = 12
    public static let starsAtEnd = 24
    public static let hillSinkPoints = 24.0

    /// 12 stars at the start, 24 by the end, fading in one by one (never going back).
    public static func starCount(_ p: Double) -> Int {
        starsAtStart + Int((Double(starsAtEnd - starsAtStart) * clamp(p)).rounded(.down))
    }

    /// How far the hills have sunk, in points.
    public static func hillSink(_ p: Double) -> Double {
        hillSinkPoints * clamp(p)
    }

    /// The moon along a gentle arc, as fractions of the sky's width and height from its
    /// top-left: it rises from the left, tops the arc in the middle, and settles at the right.
    /// The arc stays under the header (its peak is 22% down) and clear of the choices below it.
    public static func moon(_ p: Double) -> (x: Double, y: Double) {
        let t = clamp(p)
        return (0.16 + 0.68 * t, 0.30 - 0.08 * sin(Double.pi * t))
    }

    /// 0 = the night color, 1 = the deep color.
    public static func background(_ p: Double) -> Double {
        clamp(p)
    }

    /// Reduce Motion shows five checkpoints and nothing in between: 0, .25, .5, .75 and 1.
    public static func checkpoint(_ p: Double) -> Double {
        let t = clamp(p)
        if t >= 1 { return 1 }
        return (t * 4).rounded(.down) / 4
    }

    private static func clamp(_ p: Double) -> Double { min(max(p, 0), 1) }
}

/// What the screen's idle timer is told: off while a session runs, back to normal after.
public protocol IdleTimerControlling: Sendable {
    func setDisabled(_ disabled: Bool)
}

/// Where a session is remembered (SwiftData, local): when it began, how long it was planned for,
/// and whether it ran its whole time.
public protocol WindDownSessionStoring: Sendable {
    func begin(start: Date, plannedMinutes: Int) async -> UUID
    func finish(_ id: UUID, completed: Bool) async
}
