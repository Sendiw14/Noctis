import Foundation

/// What the Apple Watch app is able to say right now (APP_RULES.md R50, R51): the snapshot's data state and whether it is for today, in
/// the Watch's own words. Pure, and built on `WidgetTimelineBuilder.entry`, so the Watch follows the very rules the widgets do: a snapshot
/// for an earlier day is "waiting for today", never yesterday's numbers as today's, and old numbers say how old they are.
public enum WatchState: Equatable, Sendable {
    /// Full data for today.
    case ok
    /// A snapshot for an earlier day (a day starts at 4 AM): the iPhone has not sent last night's.
    case waitingForToday
    /// The newest Health data is old: the last known numbers, and when they are from.
    case stale(since: Date)
    /// Fewer than five nights so far.
    case learning(nightsSoFar: Int)
    /// Recovery from sleep alone: no HRV or resting heart rate.
    case sleepOnly
    /// Health holds nothing NOCTIS can use yet.
    case empty
    /// Apple Health has not been connected on the iPhone.
    case noPermission
    /// Recent data, but no sleep ended last night.
    case gap
    /// The iPhone has not sent one yet (or sent one this Watch cannot read).
    case noSnapshotYet

    /// The state at `now`. `calendar` is the person's: a day starts at 4 AM on it.
    public static func map(_ snapshot: WidgetSnapshot?, now: Date, calendar: Calendar) -> WatchState {
        let entry = WidgetTimelineBuilder.entry(for: snapshot, at: now, calendar: calendar)
        guard let snapshot else { return .noSnapshotYet }
        guard entry.scene == .ready else { return .waitingForToday }
        switch snapshot.state {
        case .full: return .ok
        case .sleepOnly: return .sleepOnly
        case .learning(let nights): return .learning(nightsSoFar: nights)
        case .empty: return .empty
        case .noPermission: return .noPermission
        case .gap: return .gap
        case .stale(let hours):
            // The newest data was `hours` old when the snapshot was made.
            return .stale(since: snapshot.generatedAt.addingTimeInterval(-TimeInterval(hours) * 3600))
        }
    }

    /// Whether the Watch may show a recovery score and last night's numbers: only with numbers for today, or the last known ones marked as old.
    public var showsNumbers: Bool {
        switch self {
        case .ok, .sleepOnly, .stale: true
        case .waitingForToday, .learning, .empty, .noPermission, .gap, .noSnapshotYet: false
        }
    }

    /// Whether the numbers are old ones (shown with their age, never as today's).
    public var isStale: Bool {
        if case .stale = self { true } else { false }
    }

    /// Whether the Watch can do something about it by itself: nothing it can fix; the iPhone has to open NOCTIS.
    public var needsIPhone: Bool {
        switch self {
        case .waitingForToday, .empty, .noPermission, .noSnapshotYet: true
        case .ok, .stale, .learning, .sleepOnly, .gap: false
        }
    }
}
