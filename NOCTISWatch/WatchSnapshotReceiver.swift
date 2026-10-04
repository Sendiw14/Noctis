import Foundation
import NoctisWatchKit
import NoctisWidgetKit
import WatchConnectivity

/// The one place on the Watch that names WatchConnectivity (a test holds it to that, with the iPhone's driver): it receives what the person's own iPhone
/// sends, hands it to `WatchInbox` (which stores it and applies the data epoch), and tells the model (APP_RULES.md R50, R52). It reads no Health and
/// sends nothing but one request: "update" ("Ask iPhone to update").
final class WatchSnapshotReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {
    /// What a request for an update came to.
    enum RequestOutcome: Equatable, Sendable {
        case accepted
        case unreachable
        case failed
    }

    private let inbox: WatchInbox?
    private let didChange: @Sendable (_ held: (snapshot: WidgetSnapshot, receivedAt: Date?)?) -> Void
    private let didChangeReachability: @Sendable (Bool) -> Void
    private let reloadComplications: @Sendable () -> Void

    /// `reloadComplications` is a stub until the complications exist (part 2): it is called whenever what the Watch holds changes.
    init(
        inbox: WatchInbox?, didChange: @escaping @Sendable (_ held: (snapshot: WidgetSnapshot, receivedAt: Date?)?) -> Void,
        didChangeReachability: @escaping @Sendable (Bool) -> Void = { _ in }, reloadComplications: @escaping @Sendable () -> Void = {}
    ) {
        self.inbox = inbox
        self.didChange = didChange
        self.didChangeReachability = didChangeReachability
        self.reloadComplications = reloadComplications
        super.init()
    }

    /// Starts the session. What the iPhone sent while the app was not running is waiting in `receivedApplicationContext`: it is applied once the
    /// session is active.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// What the app holds now.
    var held: (snapshot: WidgetSnapshot, receivedAt: Date?)? { inbox?.load() }

    // MARK: Receiving

    private func apply(_ dictionary: [String: Any]) {
        guard let inbox, let context = WatchContext(dictionary: dictionary) else { return }
        switch inbox.receive(context, now: Date()) {
        case .stored, .wiped, .cleared:
            didChange(inbox.load())
            reloadComplications()
        case .ignoredOlderEpoch, .ignoredOlderSnapshot, .ignoredUnreadable:
            break
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        // The newest context the iPhone queued, including one that arrived while this app was not running.
        apply(session.receivedApplicationContext)
        didChangeReachability(session.isReachable)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    /// A complication transfer carries the same dictionary.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        apply(userInfo)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        didChangeReachability(session.isReachable)
    }

    // MARK: Asking

    /// "Ask iPhone to update": a message only while the iPhone can be reached. It carries no content and the reply carries none.
    func requestUpdate() async -> RequestOutcome {
        guard WCSession.isSupported() else { return .unreachable }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return .unreachable }
        return await withCheckedContinuation { continuation in
            session.sendMessage(
                ["request": "update"],
                replyHandler: { reply in continuation.resume(returning: reply["accepted"] as? Bool == true ? .accepted : .failed) },
                errorHandler: { _ in continuation.resume(returning: .failed) }
            )
        }
    }

    // MARK: Background

    /// The work of `.backgroundTask(.watchConnectivity)`: the session is started and the pending context delivered before this returns, and it always
    /// returns (a time limit), so the system's task is completed on every path.
    func finishPendingContent() async {
        activate()
        _ = await WatchBackgroundDrain.wait(
            hasContentPending: { WCSession.isSupported() ? WCSession.default.hasContentPending : false },
            sleep: { try? await Task.sleep(for: .seconds($0)) }
        )
    }
}
