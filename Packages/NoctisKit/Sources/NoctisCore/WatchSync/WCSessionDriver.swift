import Foundation
import WatchConnectivity

/// The one place on the iPhone that names WatchConnectivity (a test holds it to that): `WCSession` over the protocol the sync uses. It sends only
/// what `WatchSyncService` hands it, to the person's own paired Apple Watch, over Bluetooth or Wi-Fi. Nothing goes to a server.
public nonisolated final class WCSessionDriver: NSObject, WatchSessionDriving, WCSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var onChange: (@Sendable () -> Void)?
    private var onUpdateRequested: (@Sendable () -> Void)?

    public override init() {
        super.init()
    }

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    public var isSupported: Bool { WCSession.isSupported() }
    public var isPaired: Bool { session?.isPaired ?? false }
    public var isWatchAppInstalled: Bool { session?.isWatchAppInstalled ?? false }
    public var isComplicationEnabled: Bool { session?.isComplicationEnabled ?? false }
    public var isReachable: Bool { session?.isReachable ?? false }
    public var remainingComplicationTransfers: Int { session?.remainingComplicationUserInfoTransfers ?? 0 }

    public var activation: WatchActivation {
        switch session?.activationState {
        case .activated?: .activated
        case .inactive?: .inactive
        default: .notActivated
        }
    }

    public func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    public func setHandlers(onChange: @escaping @Sendable () -> Void, onUpdateRequested: @escaping @Sendable () -> Void) {
        lock.withLock {
            self.onChange = onChange
            self.onUpdateRequested = onUpdateRequested
        }
    }

    public func updateApplicationContext(_ context: [String: Any]) throws {
        guard let session else { throw WatchSessionError.notSupported }
        try session.updateApplicationContext(context)
    }

    public func transferCurrentComplicationUserInfo(_ info: [String: Any]) -> Bool {
        guard let session else { return false }
        _ = session.transferCurrentComplicationUserInfo(info)
        return true
    }

    private func changed() {
        let handler = lock.withLock { onChange }
        handler?()
    }

    // MARK: WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) { changed() }

    public func sessionDidBecomeInactive(_ session: WCSession) { changed() }

    public func sessionDidDeactivate(_ session: WCSession) {
        // The person switched Watches: start again so the new one is served.
        session.activate()
        changed()
    }

    public func sessionWatchStateDidChange(_ session: WCSession) { changed() }

    public func sessionReachabilityDidChange(_ session: WCSession) { changed() }

    /// The Watch asked for an update ("Ask iPhone to update" on the Watch): the answer is a fresh send, never a reply with content.
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["request"] as? String == "update" {
            let handler = lock.withLock { onUpdateRequested }
            handler?()
            replyHandler(["accepted": true])
        } else {
            replyHandler(["accepted": false])
        }
    }
}

nonisolated enum WatchSessionError: Error {
    case notSupported
}
