import DesignSystem
import Foundation
import NoctisWidgetKit

/// Sends the summary to the person's own Apple Watch (APP_RULES.md R50, R52). An actor around the session: after every snapshot the widgets' publisher
/// writes, it queues the same snapshot as the Watch's application context (the newest replaces any older one still waiting); when the day changes or
/// recovery first appears for the day it also wakes the complication, but only if the complication is on the Watch face and the day's budget of
/// transfers is above zero; and "Delete all NOCTIS data" makes it send the Watch a greater data epoch with nothing else, so the Watch wipes.
///
/// What "Delete all NOCTIS data" did about the Watch, in the words the report says.
public nonisolated enum WatchWipeOutcome: Sendable, Equatable {
    /// Queued and the Watch can be reached now.
    case sent
    /// Queued; the Watch gets it the next time it connects.
    case willApplyWhenConnected
    /// No Watch is set up with NOCTIS: there is nothing to wipe.
    case noWatch

    public var line: String {
        switch self {
        case .sent: "Apple Watch: wipe sent"
        case .willApplyWhenConnected: "Apple Watch: will apply when your Watch connects"
        case .noWatch: "Apple Watch: none set up with NOCTIS"
        }
    }
}

/// It sends to a Watch that is paired, has NOCTIS installed and has been activated, and to nothing else: no server, no other device. The only log is a
/// count of the budget left, never any content.
public actor WatchSyncService {
    private let session: any WatchSessionDriving
    private let defaults: WatchSyncDefaults
    private let clock: @Sendable () -> Date
    private let signpost: @Sendable (Int) -> Void
    /// The summary the widgets last saved, for "Send update now" when nothing was written yet in this launch (it is the same file the widgets read).
    private let stored: @Sendable () -> WidgetSnapshot?
    private var latest: WidgetSnapshot?
    private var continuations: [UUID: AsyncStream<WatchConnectionStatus>.Continuation] = [:]
    private var onUpdateRequested: (@Sendable () async -> Void)?

    public init(
        session: any WatchSessionDriving, defaults: WatchSyncDefaults = WatchSyncDefaults(), clock: @escaping @Sendable () -> Date = { Date() },
        signpost: @escaping @Sendable (Int) -> Void = { NoctisSignpost.emit(.watchComplicationBudget, number: $0) },
        stored: @escaping @Sendable () -> WidgetSnapshot? = { nil }
    ) {
        self.stored = stored
        self.session = session
        self.defaults = defaults
        self.clock = clock
        self.signpost = signpost
    }

    /// The data epoch every snapshot carries: the time of the last delete-all, or 0.
    public nonisolated var dataEpoch: Int64 { defaults.dataEpoch }

    /// Starts the session (at launch) and listens for the link changing and for the Watch asking for an update.
    public func activate(onUpdateRequested: (@Sendable () async -> Void)? = nil) {
        self.onUpdateRequested = onUpdateRequested
        session.setHandlers(
            onChange: { [weak self] in Task { await self?.linkChanged() } },
            onUpdateRequested: { [weak self] in Task { await self?.watchAskedForUpdate() } }
        )
        session.activate()
    }

    // MARK: Status

    /// The status now, readable from anywhere (the Settings page opens with it, so a Watch row never appears a moment after the page does).
    public nonisolated var currentStatus: WatchConnectionStatus {
        WatchConnectionStatus(
            isSupported: session.isSupported, isPaired: session.isPaired, isWatchAppInstalled: session.isWatchAppInstalled, activation: session.activation,
            isReachable: session.isReachable, lastSentAt: defaults.lastSentAt
        )
    }

    public func status() -> WatchConnectionStatus { currentStatus }

    /// The status now, then again each time the link changes.
    public func updates() -> AsyncStream<WatchConnectionStatus> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<WatchConnectionStatus>.makeStream()
        continuations[id] = continuation
        continuation.yield(status())
        continuation.onTermination = { [weak self] _ in Task { await self?.removeContinuation(id) } }
        return stream
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func linkChanged() {
        let current = status()
        for continuation in continuations.values { continuation.yield(current) }
    }

    private func watchAskedForUpdate() async {
        await onUpdateRequested?()
        _ = await sendNow()
    }

    // MARK: Sending

    /// A snapshot was written (by the widgets' publisher): the Watch gets the same one.
    public func publish(_ snapshot: WidgetSnapshot) {
        latest = snapshot
        guard case .sent = queue(snapshot) else { return }
        wakeComplicationIfNeeded(for: snapshot)
    }

    /// "Send update now" (Settings) and the Watch's own request: the latest snapshot again, and what happened.
    public func sendNow(_ snapshot: WidgetSnapshot? = nil) async -> WatchSendOutcome {
        if let snapshot { latest = snapshot }
        guard let summary = latest ?? stored() else { return .nothingToSend }
        return queue(summary)
    }

    /// Everything the iPhone had for the Watch is gone (a delete of the summary, not of everything): the Watch drops its copy too.
    public func forget() {
        latest = nil
        _ = queueContext(WatchContext(epoch: defaults.dataEpoch, snapshotData: nil, sentAt: clock()))
        defaults.complicationMark = nil
    }

    /// "Delete all NOCTIS data": the epoch becomes now, and the Watch is sent it with no snapshot, so it wipes. The epoch is the one value that stays.
    public func wipe() -> WatchWipeOutcome {
        let now = clock()
        // Never go backwards, whatever the clock says (a Watch ignores a lower epoch).
        defaults.dataEpoch = max(Int64(now.timeIntervalSince1970.rounded()), defaults.dataEpoch + 1)
        latest = nil
        defaults.lastSentAt = nil
        defaults.complicationMark = nil
        switch queueContext(WatchContext(epoch: defaults.dataEpoch, snapshotData: nil, sentAt: now)) {
        case .sent: return session.isReachable ? .sent : .willApplyWhenConnected
        case .notSupported, .noWatchPaired, .appNotInstalled, .nothingToSend: return .noWatch
        case .notActivated, .failed: return .willApplyWhenConnected
        }
    }

    // MARK: Plumbing

    private func queue(_ snapshot: WidgetSnapshot) -> WatchSendOutcome {
        let now = clock()
        // The snapshot carries the epoch it was made with; never send one older than the epoch the iPhone holds now.
        let stamped = snapshot.dataEpoch >= defaults.dataEpoch ? snapshot : snapshot.stamped(epoch: defaults.dataEpoch)
        guard let context = try? WatchContext(snapshot: stamped, sentAt: now), context.byteCount <= WatchContext.maximumBytes else {
            return .failed("The summary could not be prepared.")
        }
        return queueContext(context)
    }

    private func queueContext(_ context: WatchContext) -> WatchSendOutcome {
        guard session.isSupported else { return .notSupported }
        guard session.isPaired else { return .noWatchPaired }
        guard session.activation == .activated else { return .notActivated }
        guard session.isWatchAppInstalled else { return .appNotInstalled }
        do {
            try session.updateApplicationContext(context.dictionary)
        } catch {
            return .failed("The system would not queue the update.")
        }
        // The delete-all context is not "a summary sent": it must not say the Watch was last sent numbers.
        if context.snapshotData != nil { defaults.lastSentAt = context.sentAt }
        linkChanged()
        return .sent(context.sentAt)
    }

    /// Wakes the complication when the day changed or recovery first appeared for the day, within the day's budget.
    private func wakeComplicationIfNeeded(for snapshot: WidgetSnapshot) {
        let day = snapshot.forDay.description
        let hasRecovery = snapshot.recovery != nil
        // What the last wake was for: "2026-09-24:1" (that day, with a recovery).
        let marked = defaults.complicationMark?.split(separator: ":").map(String.init)
        let dayChanged = marked?.first != day
        let recoveryAppeared = hasRecovery && marked?.last != "1"
        guard dayChanged || recoveryAppeared else { return }
        guard session.isComplicationEnabled else { return }
        let budget = session.remainingComplicationTransfers
        signpost(budget)
        guard budget > 0 else { return }
        guard let context = try? WatchContext(snapshot: snapshot, sentAt: clock()) else { return }
        if session.transferCurrentComplicationUserInfo(context.dictionary) { defaults.complicationMark = "\(day):\(hasRecovery ? 1 : 0)" }
    }
}
