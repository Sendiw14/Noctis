import Foundation

/// The few values the Watch sync keeps between launches, as typed accessors over the app's one defaults handle (APP_RULES.md R52). Thread-safe, so
/// the sync's actor can use it without hopping to the main actor.
///
/// `lastSentAt` and `complicationMark` are listed in the data inventory and are removed by "Delete all NOCTIS data". `dataEpoch` is the one value
/// that is NOT: it is the time of the last delete-all, kept on purpose (under a key that does not start with `noctis.`, so the clear-everything
/// step leaves it) so that a Watch that was away can still tell it must wipe its copy. It is a single timestamp and holds nothing about the person.
public nonisolated final class WatchSyncDefaults: @unchecked Sendable {
    public static let lastSentAtKey = "noctis.watch.lastSentAt"
    public static let complicationMarkKey = "noctis.watch.complicationMark"
    /// Deliberately not under `noctis.`: it survives delete-all (see above).
    public static let dataEpochKey = "watch.dataEpoch"

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = NoctisUserDefaults.standard) {
        self.defaults = defaults
    }

    /// When the iPhone last queued a summary for the Watch.
    public var lastSentAt: Date? {
        get { lock.withLock { defaults.object(forKey: Self.lastSentAtKey) as? Double }.map { Date(timeIntervalSince1970: $0) } }
        set {
            lock.withLock {
                if let newValue {
                    defaults.set(newValue.timeIntervalSince1970.rounded(), forKey: Self.lastSentAtKey)
                } else {
                    defaults.removeObject(forKey: Self.lastSentAtKey)
                }
            }
        }
    }

    /// The day (and whether it had a recovery) the complication was last woken for: "2026-09-24:1".
    public var complicationMark: String? {
        get { lock.withLock { defaults.string(forKey: Self.complicationMarkKey) } }
        set {
            lock.withLock {
                if let newValue { defaults.set(newValue, forKey: Self.complicationMarkKey) } else { defaults.removeObject(forKey: Self.complicationMarkKey) }
            }
        }
    }

    /// Unix seconds of the last "Delete all NOCTIS data"; 0 if never.
    public var dataEpoch: Int64 {
        get { lock.withLock { Int64(defaults.integer(forKey: Self.dataEpochKey)) } }
        set { lock.withLock { defaults.set(Int(max(newValue, 0)), forKey: Self.dataEpochKey) } }
    }
}
