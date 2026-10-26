#if DEBUG
import Foundation
import NoctisCore

/// `-mockWatch connected|notReachable|notInstalled|unpaired|unsupported|connecting`: a stand-in for the link to the Apple Watch, so Settings > Apple
/// Watch can be looked at in every state on a simulator that has no paired Watch. It queues nothing anywhere: `updateApplicationContext` only counts.
/// A DEBUG aid; the real link is `WCSessionDriver` and nothing else.
nonisolated final class MockWatchSession: WatchSessionDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var queued = 0
    private let mode: String

    init(mode: String) {
        self.mode = mode
    }

    var isSupported: Bool { mode != "unsupported" }
    var isPaired: Bool { isSupported && mode != "unpaired" }
    var isWatchAppInstalled: Bool { isPaired && mode != "notInstalled" }
    var isComplicationEnabled: Bool { false }
    var isReachable: Bool { mode == "connected" }
    var activation: WatchActivation { mode == "connecting" ? .notActivated : .activated }
    var remainingComplicationTransfers: Int { 50 }

    func activate() {}

    func updateApplicationContext(_ context: [String: Any]) throws {
        lock.withLock { queued += 1 }
    }

    func transferCurrentComplicationUserInfo(_ info: [String: Any]) -> Bool { false }

    func setHandlers(onChange: @escaping @Sendable () -> Void, onUpdateRequested: @escaping @Sendable () -> Void) {}
}
#endif
