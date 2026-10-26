import Foundation

/// What the iPhone sends the Watch (APP_RULES.md R50): one property-list dictionary, small enough for `updateApplicationContext`, carrying the
/// snapshot's bytes and the data epoch. Property-list types only (`Int`, `Double`, `Data`), because that is all WatchConnectivity accepts.
///
/// The epoch is in the context as well as in the snapshot, so a context with no snapshot (the iPhone deleted everything) can still tell
/// the Watch to wipe: the Watch keeps its copy only while no greater epoch has been seen.
public struct WatchContext: Equatable, Sendable {
    /// Another format is ignored by a Watch that does not know it.
    public static let formatVersion = 1

    public var epoch: Int64
    /// The snapshot's bytes (`WidgetSnapshot.encoded()`); nil means the iPhone has no summary to send.
    public var snapshotData: Data?
    /// When the iPhone sent it.
    public var sentAt: Date

    public init(epoch: Int64, snapshotData: Data?, sentAt: Date) {
        self.epoch = max(epoch, 0)
        self.snapshotData = snapshotData
        self.sentAt = sentAt
    }

    /// A context for `snapshot`, stamped with the epoch it carries.
    public init(snapshot: WidgetSnapshot, sentAt: Date) throws {
        self.init(epoch: snapshot.dataEpoch, snapshotData: try snapshot.encoded(), sentAt: sentAt)
    }

    /// The snapshot, when there is one this build can read (another version is nil).
    public var snapshot: WidgetSnapshot? { snapshotData.flatMap(WidgetSnapshot.decode) }

    /// The epoch the Watch applies: the greater of the context's and the snapshot's own.
    public var effectiveEpoch: Int64 { max(epoch, snapshot?.dataEpoch ?? 0) }

    // MARK: Property list

    static let formatKey = "wire", epochKey = "epoch", sentAtKey = "sentAt", snapshotKey = "snapshot"

    public var dictionary: [String: Any] {
        var result: [String: Any] = [
            Self.formatKey: Self.formatVersion, Self.epochKey: Int(epoch), Self.sentAtKey: Int(sentAt.timeIntervalSince1970.rounded()),
        ]
        if let snapshotData { result[Self.snapshotKey] = snapshotData }
        return result
    }

    /// The context in `dictionary`; nil when it is not one, or is a format this build does not know.
    public init?(dictionary: [String: Any]) {
        guard let format = dictionary[Self.formatKey] as? Int, format == Self.formatVersion, let epoch = dictionary[Self.epochKey] as? Int else { return nil }
        let sent = (dictionary[Self.sentAtKey] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(timeIntervalSince1970: 0)
        self.init(epoch: Int64(epoch), snapshotData: dictionary[Self.snapshotKey] as? Data, sentAt: sent)
    }

    /// The most a context may weigh: WatchConnectivity refuses a large application context, and a snapshot is a few hundred bytes.
    public static let maximumBytes = 4096
    public var byteCount: Int { (snapshotData?.count ?? 0) + 64 }
}

/// The one preference the Watch keeps for itself (APP_RULES.md R55): whether breathing on the Watch plays haptics. It is the Watch's own, in the
/// Watch's own defaults, and is listed in the data inventory under the Apple Watch's category. A "Delete all NOCTIS data" on the iPhone resets it, with
/// the rest of what the Watch holds, when the Watch next connects.
public nonisolated enum WatchPreferenceKeys {
    public static let breathHaptics = "noctis.watch.breathHaptics"
}
