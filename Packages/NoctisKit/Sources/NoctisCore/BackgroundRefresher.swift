import DesignSystem
import Foundation

/// What to do when Apple Health wakes the app in the background (APP_RULES.md R46): refresh Home's data (which writes the widgets'
/// snapshot and reloads their timelines), safely.
///
/// - No work before setup is finished, or when Health is not authorized.
/// - Wakes that arrive together (sleep, HRV and resting heart rate are delivered separately) share one refresh; a wake right after a
///   refresh finished does nothing.
/// - The work has a time budget; the caller's completion handler is called when it ends, on every path, so HealthKit is never left waiting.
/// - Nothing polls: the only trigger is Health's own delivery, which is best-effort.
public actor BackgroundRefresher {
    public enum SkipReason: Sendable, Equatable {
        case notOnboarded
        case notAuthorized
        /// A refresh finished less than `minimumInterval` ago.
        case tooSoon
    }

    public enum Outcome: Sendable, Equatable {
        /// This wake did the refresh.
        case refreshed
        /// The work did not finish in the time budget (it carries on, and the completion handler is called).
        case timedOut
        /// Another wake was already refreshing: this one waited for it and added nothing.
        case coalesced
        case skipped(SkipReason)
    }

    /// A wake this soon after a refresh finished does nothing.
    public static let defaultMinimumInterval: TimeInterval = 60
    /// How long a background wake spends before it gives up and lets HealthKit go.
    public static let defaultTimeBudget: TimeInterval = 20

    private let isOnboarded: @Sendable () async -> Bool
    private let isAuthorized: @Sendable () async -> Bool
    private let refresh: @Sendable () async -> Void
    private let clock: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let minimumInterval: TimeInterval
    private let timeBudget: TimeInterval

    private var inFlight: Task<Outcome, Never>?
    private var lastFinished: Date?
    /// Wakes that arrived while a refresh was running and are waiting for it (coalesced): a test looks at this before it lets the refresh go.
    public private(set) var waitingWakes = 0

    public init(
        isOnboarded: @escaping @Sendable () async -> Bool, isAuthorized: @escaping @Sendable () async -> Bool, refresh: @escaping @Sendable () async -> Void,
        minimumInterval: TimeInterval = BackgroundRefresher.defaultMinimumInterval, timeBudget: TimeInterval = BackgroundRefresher.defaultTimeBudget,
        clock: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.isOnboarded = isOnboarded
        self.isAuthorized = isAuthorized
        self.refresh = refresh
        self.minimumInterval = minimumInterval
        self.timeBudget = timeBudget
        self.clock = clock
        self.sleep = sleep
    }

    /// One wake from Health. Returns when it is finished with, however it ended.
    public func handleWake() async -> Outcome {
        if let inFlight {
            waitingWakes += 1
            _ = await inFlight.value
            waitingWakes -= 1
            return .coalesced
        }
        let task = Task { await self.run() }
        inFlight = task
        let outcome = await task.value
        inFlight = nil
        return outcome
    }

    private func run() async -> Outcome {
        guard await isOnboarded() else { return .skipped(.notOnboarded) }
        guard await isAuthorized() else { return .skipped(.notAuthorized) }
        if let lastFinished, clock().timeIntervalSince(lastFinished) < minimumInterval { return .skipped(.tooSoon) }
        NoctisSignpost.begin(.backgroundRefresh)
        let finished = await withinBudget()
        NoctisSignpost.end(.backgroundRefresh)
        lastFinished = clock()
        return finished ? .refreshed : .timedOut
    }

    /// Runs the refresh, and gives up waiting for it after the time budget. The first of the two to finish decides; the other is left
    /// (a refresh that outlasts the budget carries on and publishes when it is done).
    private func withinBudget() async -> Bool {
        let work = refresh
        let wait = sleep
        let budget = timeBudget
        return await withCheckedContinuation { continuation in
            let gate = OneShot(continuation)
            Task {
                await work()
                gate.finish(true)
            }
            Task {
                await wait(budget)
                gate.finish(false)
            }
        }
    }
}

/// Resumes a continuation once, whichever caller gets there first.
private nonisolated final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: Bool) {
        let pending = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
