import Foundation

/// A Keychain item outlives an uninstall, a UserDefaults marker does not (S1B-B04, X-11). At launch, before the account is read: if this copy of the app has never
/// started (no marker) and there is no database either, the Keychain item belongs to an earlier install and is cleared, so a reinstalled app starts signed out
/// instead of showing a sign-in the person may expect to be gone. The database test is what keeps an update, or a restore that lost the marker, signed in: only an
/// install with nothing of its own on disk loses the item. Sign in with Apple is one tap again. Never touches anything but the identifier.
public nonisolated struct FreshInstallGuard {
    public static let markerKey = "noctis.install.marker"

    private let defaults: UserDefaults
    private let hasDatabase: () -> Bool
    private let keychain: any AccountKeychain

    public init(
        defaults: UserDefaults = NoctisUserDefaults.standard, keychain: any AccountKeychain = SystemAccountKeychain(),
        hasDatabase: @escaping () -> Bool = { FileManager.default.fileExists(atPath: NoctisStore.defaultURL.path) }
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.hasDatabase = hasDatabase
    }

    /// Clears the identifier on a fresh install and records that this copy has started. True when it cleared one. When the Keychain cannot be asked yet (the iPhone
    /// has not been unlocked since it started) nothing is cleared and nothing is recorded, so the next launch asks again (S1B-R-16).
    @discardableResult
    public func run() -> Bool {
        guard defaults.object(forKey: Self.markerKey) == nil else { return false }
        let lookup = keychain.lookup()
        guard lookup != .unavailable else { return false }
        let cleared = lookup == .found && !hasDatabase()
        if cleared { keychain.delete() }
        defaults.set(true, forKey: Self.markerKey)
        return cleared
    }
}
