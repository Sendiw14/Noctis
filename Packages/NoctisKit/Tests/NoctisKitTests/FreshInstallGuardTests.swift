import Foundation
import Testing

@testable import NoctisCore

// A sign-in left in the Keychain by an earlier install is not picked up by a fresh one (S1B-B04), and an update never signs anyone out.

struct FreshInstallGuardTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "noctis.install.\(UUID().uuidString)") ?? .standard }

    @Test func aFreshInstallWithAnOldKeychainItemStartsSignedOut() {
        let keychain = MemoryAccountKeychain(userID: "left-by-an-earlier-install")
        let defaults = defaults()
        let cleared = FreshInstallGuard(defaults: defaults, keychain: keychain, hasDatabase: { false }).run()
        #expect(cleared && keychain.read() == nil)
        #expect(defaults.object(forKey: FreshInstallGuard.markerKey) != nil, "this copy has now started")
    }

    @Test func anUpdateWithNoMarkerButADatabaseStaysSignedIn() {
        let keychain = MemoryAccountKeychain(userID: "someone")
        let cleared = FreshInstallGuard(defaults: defaults(), keychain: keychain, hasDatabase: { true }).run()
        #expect(!cleared && keychain.read() == "someone", "the marker is new to an install that already has its own data")
    }

    @Test func aLaterLaunchNeverTouchesTheItem() {
        let keychain = MemoryAccountKeychain(userID: "someone")
        let defaults = defaults()
        let first = FreshInstallGuard(defaults: defaults, keychain: keychain, hasDatabase: { true })
        first.run()
        let signedInAfterwards = MemoryAccountKeychain(userID: "signed-in-after-the-first-launch")
        let again = FreshInstallGuard(defaults: defaults, keychain: signedInAfterwards, hasDatabase: { false })
        #expect(!again.run() && signedInAfterwards.read() == "signed-in-after-the-first-launch", "with the marker there, the database is not asked")
    }

    @Test func aFreshInstallWithNothingInTheKeychainJustRecordsTheStart() {
        let keychain = MemoryAccountKeychain()
        let defaults = defaults()
        #expect(!FreshInstallGuard(defaults: defaults, keychain: keychain, hasDatabase: { false }).run())
        #expect(defaults.object(forKey: FreshInstallGuard.markerKey) != nil)
    }

    /// A keychain that cannot be asked yet: the iPhone has not been unlocked since it started.
    private final class LockedKeychain: AccountKeychain, @unchecked Sendable {
        let item = "left-by-an-earlier-install"
        var deleted = false
        func read() -> String? { nil }
        func write(_ userID: String) -> Bool { false }
        func delete() { deleted = true }
        func lookup() -> KeychainLookup { .unavailable }
    }

    @Test func aKeychainThatCannotBeAskedYetIsNeitherClearedNorMarked() {
        let defaults = defaults()
        let locked = LockedKeychain()
        #expect(!FreshInstallGuard(defaults: defaults, keychain: locked, hasDatabase: { false }).run())
        #expect(!locked.deleted && defaults.object(forKey: FreshInstallGuard.markerKey) == nil, "no marker: the next launch asks again")
        // The next launch can ask: the stale item is found and cleared.
        let unlocked = MemoryAccountKeychain(userID: "left-by-an-earlier-install")
        #expect(FreshInstallGuard(defaults: defaults, keychain: unlocked, hasDatabase: { false }).run() && unlocked.read() == nil)
    }

    @Test func theLookupSaysFoundNotFoundAndDefaultsForAMemoryKeychain() {
        #expect(MemoryAccountKeychain(userID: "x").lookup() == .found && MemoryAccountKeychain().lookup() == .notFound)
    }

    @Test func theSystemKeychainDistinguishesNothingFoundFromCannotAsk() throws {
        let text = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisCore/Account/AccountStore.swift"), encoding: .utf8)
        #expect(text.contains("case errSecItemNotFound: return .notFound") && text.contains("default: return .unavailable"))
    }

    @Test func theGuardRunsBeforeTheAccountIsRead() async throws {
        let text = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/AppRoot/AppContainer.swift"), encoding: .utf8)
        let guardCall = try #require(text.range(of: "FreshInstallGuard().run()"))
        let account = try #require(text.range(of: "AccountStore("))
        #expect(guardCall.lowerBound < account.lowerBound)
    }

    @Test func theMarkerIsInTheInventoryAndHoldsNothingAboutThePerson() throws {
        let inventory = DataInventory.shared.categories.first { $0.id == .appState }
        let keys = inventory?.locations.flatMap { location -> [String] in
            if case .defaults(let keys) = location { return keys }
            return []
        }
        #expect(keys?.contains(FreshInstallGuard.markerKey) == true)
    }
}
