import Foundation
import PremiumKit

/// The last tier NOCTIS saw, in the app's defaults (APP_RULES.md R57): used only until the first answer from the App Store (a local call), then overwritten,
/// so a Premium person never sees a screen of locks for the moment before it. It is one word, not a record of anything. "Reset preferences" leaves it; "Delete
/// all NOCTIS data" removes it with every other key. Listed in the data inventory under the subscription.
public nonisolated struct EntitlementCache {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = NoctisUserDefaults.standard) {
        self.defaults = defaults
    }

    public func read() -> CachedTier {
        defaults.string(forKey: PremiumKeys.cachedTier).flatMap(CachedTier.init(rawValue:)) ?? .free
    }

    public func write(_ tier: CachedTier) {
        defaults.set(tier.rawValue, forKey: PremiumKeys.cachedTier)
    }

    public func clear() {
        defaults.removeObject(forKey: PremiumKeys.cachedTier)
    }
}

/// The free Coach questions used today, in the app's defaults: a date and a count, never a question (R60). `inMemory()` is for a fixed-tier gate (a preview,
/// a DEBUG launch) that must not touch the app's defaults.
public nonisolated struct CoachQuotaStore: Sendable {
    private let load: @Sendable () -> CoachQuotaState
    private let save: @Sendable (CoachQuotaState) -> Void
    private let remove: @Sendable () -> Void

    public init(defaults: UserDefaults = NoctisUserDefaults.standard) {
        nonisolated(unsafe) let defaults = defaults
        load = { defaults.string(forKey: PremiumKeys.coachQuota).flatMap(CoachQuotaState.init(stored:)) ?? CoachQuotaState() }
        save = { defaults.set($0.stored, forKey: PremiumKeys.coachQuota) }
        remove = { defaults.removeObject(forKey: PremiumKeys.coachQuota) }
    }

    private init(load: @escaping @Sendable () -> CoachQuotaState, save: @escaping @Sendable (CoachQuotaState) -> Void, remove: @escaping @Sendable () -> Void) {
        self.load = load
        self.save = save
        self.remove = remove
    }

    /// A store that keeps the count in memory only.
    public static func inMemory() -> CoachQuotaStore {
        let box = Box()
        return CoachQuotaStore(load: { box.value }, save: { box.value = $0 }, remove: { box.value = CoachQuotaState() })
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = CoachQuotaState()
        var value: CoachQuotaState {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    public func read() -> CoachQuotaState { load() }
    public func write(_ state: CoachQuotaState) { save(state) }
    public func clear() { remove() }
}
