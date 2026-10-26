import BreathingKit
import Foundation
import NoctisWidgetKit

// Breathing on the Apple Watch (APP_RULES.md R55): the patterns and the schedule are `BreathingKit`'s, the same as the iPhone's. Everything here is pure,
// with the system's sessions and haptics behind two small protocols, so the rules are unit tests: what the haptics do and when (only at a change of
// phase, and once at the end), what happens when the extended runtime session starts, is about to expire, or ends, and what the screen says. The Watch
// app plays them with `WKInterfaceDevice` and `WKExtendedRuntimeSession`. Nothing here reads Health or writes it: no Mindful Minutes (ROADMAP.md).

// MARK: - Haptics

/// What the wrist feels, by name: the Watch app maps each to one of the system's haptic types (`WKHapticType`): the direction-up tap for an inhale, the
/// direction-down tap for an exhale, a click for a hold, and the success haptic at the end.
public nonisolated enum BreathHaptic: String, Sendable, Equatable, CaseIterable {
    case inhale
    case hold
    case exhale
    case done
}

public nonisolated struct BreathHapticEvent: Equatable, Sendable {
    /// Seconds from the start of the exercise.
    public var time: Double
    public var haptic: BreathHaptic

    public init(time: Double, haptic: BreathHaptic) {
        self.time = time
        self.haptic = haptic
    }
}

public nonisolated enum BreathHapticPlanner {
    public static func haptic(for kind: BreathingPhaseKind) -> BreathHaptic {
        switch kind {
        case .inhale: .inhale
        case .hold: .hold
        case .exhale: .exhale
        }
    }

    /// One haptic at the start of every phase of every breath and one when the exercise ends, and nothing in between: the wrist is told when the
    /// breath changes, never during it.
    public static func events(for schedule: BreathingSchedule) -> [BreathHapticEvent] {
        var events: [BreathHapticEvent] = []
        var time = 0.0
        for _ in 0..<schedule.cycles {
            for phase in schedule.phases {
                events.append(BreathHapticEvent(time: time, haptic: haptic(for: phase.kind)))
                time += Double(phase.seconds)
            }
        }
        events.append(BreathHapticEvent(time: Double(schedule.totalSeconds), haptic: .done))
        return events
    }
}

/// Plays a haptic on the wrist.
public protocol BreathHapticPlaying: AnyObject {
    func play(_ haptic: BreathHaptic)
}

// MARK: - The extended runtime session

/// Why the system ended a session.
public nonisolated enum ExtendedRuntimeInvalidation: Sendable, Equatable {
    /// It ended normally (this app asked it to).
    case none
    /// Another session of this app was already running.
    case sessionInProgress
    /// It reached its time limit.
    case expired
    /// The app lost frontmost status (the Digital Crown, another app).
    case resignedFrontmost
    /// The Watch is in a state that does not allow this session now.
    case suppressedBySystem
    /// It could not start or ended with an error (a missing background mode, for one).
    case error
}

public nonisolated enum ExtendedRuntimeEvent: Sendable, Equatable {
    case started
    /// About to expire: everything must be done before then.
    case willExpire
    case invalidated(ExtendedRuntimeInvalidation)
}

/// A mindfulness `WKExtendedRuntimeSession`, which keeps the app running with the wrist down and the screen asleep so the haptics go on. The real one is
/// `WKExtendedRuntimeSession`; tests use a fake that sends the events by hand.
public protocol ExtendedRuntimeClient: AnyObject {
    /// Told as the session starts, is about to expire and ends (set before `start()`).
    var onEvent: (@Sendable (ExtendedRuntimeEvent) -> Void)? { get set }
    func start()
    /// Ends it (a no-op when it never started).
    func invalidate()
}

// MARK: - The session

/// What the exercise is doing, from the start of the breath to the end of it. Pure: events in, effects out, and the time is passed in.
public nonisolated struct BreathSessionModel: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case running
        /// The exercise cannot go on with the wrist down (no runtime session to keep it running): it waits for the wrist to be raised.
        case paused
        /// `completed` is false when the person ended it early.
        case finished(completed: Bool)
    }

    public enum Runtime: Equatable, Sendable {
        case notStarted
        case starting
        case running
        case ended
    }

    public enum Event: Equatable, Sendable {
        case runtime(ExtendedRuntimeEvent)
        case becameActive
        case becameInactive
        case tick
        case cancel
    }

    public enum Effect: Equatable, Sendable {
        case startRuntime
        case invalidateRuntime
    }

    public let schedule: BreathingSchedule
    public private(set) var status: Status = .running
    public private(set) var runtime: Runtime = .notStarted
    public private(set) var isActive: Bool
    /// The runtime session said it is about to end.
    public private(set) var isExpiring = false
    private var accumulated: TimeInterval = 0
    private var resumedAt: Date?

    /// A run that has just begun at `now`; the runtime session is asked for in `begin()`.
    public init(schedule: BreathingSchedule, now: Date, isActive: Bool = true) {
        self.schedule = schedule
        self.isActive = isActive
        resumedAt = now
    }

    /// The seconds of the exercise gone at `now`; frozen while paused, and never past the end.
    public func elapsed(at now: Date) -> TimeInterval {
        let running = resumedAt.map { max(now.timeIntervalSince($0), 0) } ?? 0
        return min(accumulated + running, Double(schedule.totalSeconds))
    }

    /// What the screen says while paused.
    public var pauseMessage: String? { status == .paused ? WatchBreathCopy.raiseWrist : nil }

    public var isFinished: Bool {
        if case .finished = status { true } else { false }
    }

    /// The first thing a run does: ask for the runtime session.
    public mutating func begin() -> [Effect] {
        guard runtime == .notStarted else { return [] }
        runtime = .starting
        return [.startRuntime]
    }

    private mutating func pause(at now: Date) {
        guard status == .running else { return }
        accumulated = elapsed(at: now)
        resumedAt = nil
        status = .paused
    }

    private mutating func resume(at now: Date) {
        guard status == .paused else { return }
        resumedAt = now
        status = .running
    }

    private mutating func finish(completed: Bool, at now: Date) -> [Effect] {
        accumulated = completed ? Double(schedule.totalSeconds) : elapsed(at: now)
        resumedAt = nil
        status = .finished(completed: completed)
        return runtime == .running || runtime == .starting ? [.invalidateRuntime] : []
    }

    public mutating func apply(_ event: Event, at now: Date) -> [Effect] {
        guard !isFinished else { return [] }
        switch event {
        case .runtime(.started):
            runtime = .running
            // A run that paused before the session came up goes on: the session keeps it running with the wrist down.
            resume(at: now)
        case .runtime(.willExpire):
            isExpiring = true
        case .runtime(.invalidated):
            runtime = .ended
            // With the screen on the exercise goes on as it does without a session; with the wrist down it cannot, and waits.
            if !isActive { pause(at: now) }
        case .becameActive:
            isActive = true
            resume(at: now)
        case .becameInactive:
            isActive = false
            if runtime != .running { pause(at: now) }
        case .tick:
            if status == .running, elapsed(at: now) >= Double(schedule.totalSeconds) { return finish(completed: true, at: now) }
        case .cancel:
            return finish(completed: false, at: now)
        }
        return []
    }
}

/// Runs a `BreathSessionModel` against the system: asks for the runtime session, plays the haptics when their time comes, and ends the session when the
/// exercise does. It does no timing of its own: the app calls `tick(at:)` often while the exercise runs.
@MainActor
public final class BreathSessionDriver {
    public private(set) var model: BreathSessionModel
    private let runtime: any ExtendedRuntimeClient
    private let haptics: any BreathHapticPlaying
    private let hapticsEnabled: Bool
    private let events: [BreathHapticEvent]
    private var nextEvent = 0

    /// `clock` is what the runtime session's own events are stamped with (the system's, or a test's).
    public init(
        schedule: BreathingSchedule, now: Date, isActive: Bool = true, hapticsEnabled: Bool, runtime: any ExtendedRuntimeClient,
        haptics: any BreathHapticPlaying,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        model = BreathSessionModel(schedule: schedule, now: now, isActive: isActive)
        self.runtime = runtime
        self.haptics = haptics
        self.hapticsEnabled = hapticsEnabled
        events = BreathHapticPlanner.events(for: schedule)
        runtime.onEvent = { [weak self] event in
            Task { @MainActor in self?.runtimeEvent(event, at: clock()) }
        }
    }

    /// Begins: the runtime session is asked for and the first breath's haptic is played.
    public func begin(at now: Date) {
        perform(model.begin())
        playDue(at: now)
    }

    public func tick(at now: Date) { send(.tick, at: now) }

    public func cancel(at now: Date) { send(.cancel, at: now) }

    public func sceneBecameActive(at now: Date) { send(.becameActive, at: now) }

    public func sceneBecameInactive(at now: Date) { send(.becameInactive, at: now) }

    /// What the runtime session reports.
    public func runtimeEvent(_ event: ExtendedRuntimeEvent, at now: Date) { send(.runtime(event), at: now) }

    private func send(_ event: BreathSessionModel.Event, at now: Date) {
        perform(model.apply(event, at: now))
        playDue(at: now)
    }

    private func perform(_ effects: [BreathSessionModel.Effect]) {
        for effect in effects {
            switch effect {
            case .startRuntime: runtime.start()
            case .invalidateRuntime: runtime.invalidate()
            }
        }
    }

    /// Plays the haptic of every change of phase that has come, once. If the timer was late and more than one is due, only the newest is played: the
    /// wrist is never given a burst. Nothing plays while paused or after an early end, and the success haptic only when the exercise completed.
    private func playDue(at now: Date) {
        let elapsed = model.elapsed(at: now)
        var due: BreathHapticEvent?
        while nextEvent < events.count, events[nextEvent].time <= elapsed {
            due = events[nextEvent]
            nextEvent += 1
        }
        guard let due, hapticsEnabled else { return }
        if due.haptic == .done, model.status != .finished(completed: true) { return }
        if model.status == .finished(completed: false) { return }
        haptics.play(due.haptic)
    }
}

// MARK: - What the screen says

public nonisolated enum WatchBreathCopy {
    public static let tagline = "A slow breathing exercise."
    public static let button = "Breathe"
    public static let raiseWrist = "Raise your wrist to continue"
    public static let done = "Done"
    public static let again = "Breathe again"
    public static let close = "Close"
    public static let start = "Start"
    public static let end = "End"
    public static let hapticsToggle = "Breathing haptics"
    public static let inhale = "Breathe in"
    public static let hold = "Hold"
    public static let exhale = "Breathe out"

    public static func phase(_ kind: BreathingPhaseKind) -> String {
        switch kind {
        case .inhale: inhale
        case .hold: hold
        case .exhale: exhale
        }
    }

    /// "2 min".
    public static func minutes(_ value: Int) -> String { "\(value) min" }
}

/// What one frame of the exercise shows, from where it is.
public nonisolated struct WatchBreathFrame: Equatable, Sendable {
    public var phase: String
    /// The seconds the phase has left, counting down: its length at the start, 1 in its last second.
    public var seconds: Int
    /// How full the lungs are, 0...1: the circle's size, or the bar's length with Reduce Motion.
    public var level: Double
    public var kind: BreathingPhaseKind

    /// The circle never shrinks to nothing: this share of its room when empty.
    public static let smallestScale = 0.4

    public init(moment: BreathingMoment) {
        phase = WatchBreathCopy.phase(moment.kind)
        seconds = moment.countdown
        level = moment.level
        kind = moment.kind
    }

    /// The circle's size as a share of its room.
    public var circleScale: Double { Self.smallestScale + (1 - Self.smallestScale) * level }

    public var accessibilityLabel: String { "\(phase), \(seconds)" }
}

/// The choices before a session starts: a pattern and a length, the iPhone's own defaults.
public nonisolated struct WatchBreathChoice: Equatable, Sendable {
    public var pattern = BreathingPattern.defaultID
    public var minutes = BreathingSchedule.defaultMinutes

    public init() {}

    public var schedule: BreathingSchedule { BreathingSchedule(pattern: BreathingPattern.pattern(pattern), minutes: minutes) }
}

/// The Watch's own preference: breathing haptics, on unless switched off. Its key is listed in the data inventory (the Apple Watch's category).
public nonisolated struct WatchPreferences {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var breathHaptics: Bool {
        get { defaults.object(forKey: WatchPreferenceKeys.breathHaptics) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: WatchPreferenceKeys.breathHaptics) }
    }

    /// Back to the default: what "Delete all NOCTIS data" on the iPhone does to the Watch.
    public func reset() {
        defaults.removeObject(forKey: WatchPreferenceKeys.breathHaptics)
    }
}
