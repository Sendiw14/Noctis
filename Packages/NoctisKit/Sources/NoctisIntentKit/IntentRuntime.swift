import Foundation
import NoctisWidgetKit
import SoundKit

// What an intent needs from the app (APP_RULES.md R47). Intents never touch HealthKit, SwiftData or Coach: they read the widgets'
// snapshot, and ask the running app (the host) to do the few things that need it. The host is the app's own, installed when the app starts
// (a background launch for an audio intent starts it too), and is faked in tests.

/// Where an opening intent sends the person. The app maps each to its one `AppRoute` path (`AppModel.open`); no intent holds navigation logic.
public enum IntentDestination: Sendable, Equatable {
    case recovery
    case sleep
    case bedtime
    case windDown(autostart: Bool)
    case alarm
    case coach
}

/// What happened when an intent asked for the alarm to be set.
public enum AlarmIntentOutcome: Sendable, Equatable {
    /// Set, for this time (minutes since midnight).
    case set(minutes: Int)
    /// The system would not schedule it (AlarmKit's limit, or a failure): nothing is promised.
    case couldNotSet
    /// The system has not been allowed to schedule alarms: nothing was changed, and the app opens at the alarm sheet instead.
    case needsAuthorization
}

/// The running app, as the intents need it.
@MainActor
public protocol IntentHost: AnyObject, Sendable {
    func open(_ destination: IntentDestination)
    /// Opens the wind-down and begins it, with this length (10, 20 or 30) or the person's last.
    func startWindDown(minutes: Int?)
    /// Plays `kind`, or the last sound played (Rain before any), through the sound player; returns what was started.
    func playSleepSounds(_ kind: SoundKind?) -> SoundKind
    /// Sets tonight's wake alarm, only if alarm access was already given.
    func setTonightAlarm(minutes: Int) async -> AlarmIntentOutcome
    /// Opens Coach and asks `text`. The text is held in memory until Coach takes it; the intent keeps nothing.
    func askCoach(_ text: String)
}

/// What an intent reads: the snapshot, the clock, the calendar.
public struct IntentEnvironment: Sendable {
    public var snapshot: @Sendable () -> WidgetSnapshot?
    public var now: @Sendable () -> Date
    public var calendar: @Sendable () -> Calendar
    public var format: @Sendable () -> WidgetFormat

    public init(
        snapshot: @escaping @Sendable () -> WidgetSnapshot?, now: @escaping @Sendable () -> Date = { Date() },
        calendar: @escaping @Sendable () -> Calendar = { .autoupdatingCurrent }, format: @escaping @Sendable () -> WidgetFormat = { WidgetFormat() }
    ) {
        self.snapshot = snapshot
        self.now = now
        self.calendar = calendar
        self.format = format
    }

    /// The App Group's snapshot and the real clock.
    public static let live = IntentEnvironment(snapshot: { WidgetSnapshotStore()?.load() })
}

/// The app's side of the intents: one per process. Tests make their own and run an intent under it (`override`).
@MainActor
public final class IntentRuntime {
    public static let shared = IntentRuntime()
    /// A runtime a test installs for the intents it runs (task-local, so tests never share one).
    @TaskLocal public static var override: IntentRuntime?
    /// The runtime an intent running now should use.
    public static var current: IntentRuntime { override ?? shared }

    public var environment: IntentEnvironment
    /// How long an intent waits for the app to finish starting before it tells the person to open NOCTIS.
    public var hostWaitSeconds: Double = 8
    private var host: (any IntentHost)?
    private var waiters: [UUID: CheckedContinuation<(any IntentHost)?, Never>] = [:]

    public init(environment: IntentEnvironment = .live, host: (any IntentHost)? = nil) {
        self.environment = environment
        self.host = host
    }

    /// The app has started: its host is ready.
    public func install(_ host: any IntentHost) {
        self.host = host
        let waiting = waiters
        waiters = [:]
        for (_, continuation) in waiting { continuation.resume(returning: host) }
    }

    public func uninstall() {
        host = nil
    }

    /// The host, waiting for the app to finish starting if an intent came first (a background launch), up to `seconds`.
    public func host(waiting seconds: Double? = nil) async -> (any IntentHost)? {
        if let host { return host }
        let seconds = seconds ?? hostWaitSeconds
        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiters[id] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.expire(id)
            }
        }
    }

    private func expire(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(returning: nil)
    }
}
