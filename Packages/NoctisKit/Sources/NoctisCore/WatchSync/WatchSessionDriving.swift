import Foundation
import NoctisWidgetKit

// What the iPhone needs of its link to the Apple Watch (APP_RULES.md R50, R52), as a protocol: the sync's rules (what is sent when, and what
// is not) are unit tests against a fake, and only `WCSessionDriver` touches WatchConnectivity.

public nonisolated enum WatchActivation: Sendable, Equatable {
    case notActivated
    case inactive
    case activated
}

/// Why something was not sent, or that it was.
public nonisolated enum WatchSendOutcome: Sendable, Equatable {
    /// Queued for the Watch (it arrives when the Watch next runs, if it is not reachable now).
    case sent(Date)
    /// This device cannot pair with a Watch.
    case notSupported
    case noWatchPaired
    /// A Watch is paired but NOCTIS is not installed on it.
    case appNotInstalled
    case notActivated
    /// NOCTIS has no summary yet to send.
    case nothingToSend
    case failed(String)

}

/// The state of the link, as far as the iPhone can tell.
public nonisolated struct WatchConnectionStatus: Sendable, Equatable {
    public enum Connection: Sendable, Equatable {
        case notSupported
        case noWatchPaired
        case appNotInstalled
        case notActivated
        /// The Watch can be reached now.
        case connected
        /// The Watch app is installed but cannot be reached now (it will get the next update when it connects).
        case notReachable
    }

    public var isSupported: Bool
    public var isPaired: Bool
    public var isWatchAppInstalled: Bool
    public var activation: WatchActivation
    public var isReachable: Bool
    public var lastSentAt: Date?

    public init(
        isSupported: Bool, isPaired: Bool, isWatchAppInstalled: Bool, activation: WatchActivation, isReachable: Bool, lastSentAt: Date? = nil
    ) {
        self.isSupported = isSupported
        self.isPaired = isPaired
        self.isWatchAppInstalled = isWatchAppInstalled
        self.activation = activation
        self.isReachable = isReachable
        self.lastSentAt = lastSentAt
    }

    public static let unsupported = WatchConnectionStatus(
        isSupported: false, isPaired: false, isWatchAppInstalled: false, activation: .notActivated, isReachable: false)

    public var connection: Connection {
        guard isSupported else { return .notSupported }
        guard isPaired else { return .noWatchPaired }
        guard activation == .activated else { return .notActivated }
        guard isWatchAppInstalled else { return .appNotInstalled }
        return isReachable ? .connected : .notReachable
    }

    /// Whether a Watch is paired: the Settings row appears only then (R29: nothing is shown that cannot work).
    public var showsSettingsRow: Bool { isSupported && isPaired }

    /// Whether an update can be queued now.
    public var canSend: Bool {
        switch connection {
        case .connected, .notReachable: true
        case .notSupported, .noWatchPaired, .appNotInstalled, .notActivated: false
        }
    }
}

/// The link to the Watch. The real one is a thin wrapper over `WCSession`; tests use a fake.
public nonisolated protocol WatchSessionDriving: AnyObject, Sendable {
    var isSupported: Bool { get }
    var isPaired: Bool { get }
    var isWatchAppInstalled: Bool { get }
    var isComplicationEnabled: Bool { get }
    var isReachable: Bool { get }
    var activation: WatchActivation { get }
    /// How many more complication transfers the system will take today (a budget of 50).
    var remainingComplicationTransfers: Int { get }
    /// Starts the session. Called once, at launch.
    func activate()
    /// Queues `context` as the Watch's latest application context (the newest replaces any older one still waiting).
    func updateApplicationContext(_ context: [String: Any]) throws
    /// Queues a transfer that wakes the complication, and counts against the budget. False when the system refused it.
    func transferCurrentComplicationUserInfo(_ info: [String: Any]) -> Bool
    /// Told whenever the link changes (activation, pairing, installing, reachability) and when the Watch asks for an update.
    func setHandlers(onChange: @escaping @Sendable () -> Void, onUpdateRequested: @escaping @Sendable () -> Void)
}
