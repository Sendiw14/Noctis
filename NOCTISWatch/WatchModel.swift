import Foundation
import NoctisWatchKit
import NoctisWidgetKit
import Observation

/// What the Watch app's screens read (APP_RULES.md R50, R51): the held snapshot and when it arrived. It runs no engine and reads no Health: it holds
/// what the iPhone sent, and `WatchState` says what that allows the screens to say.
@MainActor
@Observable
final class WatchModel {
    private(set) var snapshot: WidgetSnapshot?
    private(set) var receivedAt: Date?
    private(set) var isPhoneReachable = false

    @ObservationIgnored private(set) var receiver: WatchSnapshotReceiver?

    init() {
        let inbox = WatchInbox()
        let held = inbox?.load()
        snapshot = held?.snapshot
        receivedAt = held?.receivedAt
        receiver = WatchSnapshotReceiver(
            inbox: inbox,
            didChange: { [weak self] held in Task { @MainActor in self?.apply(held) } },
            didChangeReachability: { [weak self] reachable in Task { @MainActor in self?.isPhoneReachable = reachable } }
        )
        receiver?.activate()
    }

    private func apply(_ held: (snapshot: WidgetSnapshot, receivedAt: Date?)?) {
        snapshot = held?.snapshot
        receivedAt = held?.receivedAt
    }

    /// The state at `now`.
    func state(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> WatchState {
        WatchState.map(snapshot, now: now, calendar: calendar)
    }
}
