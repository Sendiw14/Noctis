import Foundation
import Security
import Testing

@testable import NoctisCore

// The Keychain item that holds Apple's opaque user identifier. Its write replaces the item in place and never deletes it first, so a write that fails (an iPhone that has
// not been unlocked since it started answers errSecInteractionNotAllowed) leaves the identifier that was there. The real Keychain answers no one outside the app, so the
// three calls that change the item are replaced by a fake that keeps one item and can be told to fail.

private nonisolated final class FakeKeychain: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var value: Data?
    private(set) var updates: [[String: Any]] = []
    private(set) var adds: [[String: Any]] = []
    private(set) var deletes = 0
    var updateStatus: OSStatus?
    var addStatus: OSStatus?

    var calls: KeychainCalls {
        KeychainCalls(
            update: { [self] _, attributes in
                lock.withLock {
                    updates.append(attributes)
                    if let updateStatus { return updateStatus }
                    guard value != nil else { return errSecItemNotFound }
                    value = attributes[kSecValueData as String] as? Data
                    return errSecSuccess
                }
            },
            add: { [self] attributes in
                lock.withLock {
                    adds.append(attributes)
                    if let addStatus { return addStatus }
                    value = attributes[kSecValueData as String] as? Data
                    return errSecSuccess
                }
            },
            delete: { [self] _ in
                lock.withLock {
                    deletes += 1
                    value = nil
                    return errSecSuccess
                }
            }
        )
    }

    func keychain() -> SystemAccountKeychain { SystemAccountKeychain(service: "test", account: "test", calls: calls) }
    func stored() -> String? { value.flatMap { String(data: $0, encoding: .utf8) } }
}

struct SystemAccountKeychainTests {
    @Test func theFirstWriteAddsTheItemAndDeletesNothing() {
        let fake = FakeKeychain()
        #expect(fake.keychain().write("001234.abcdef"))
        #expect(fake.stored() == "001234.abcdef" && fake.adds.count == 1 && fake.deletes == 0)
    }

    @Test func aLaterWriteUpdatesInPlaceWithNoAddAndNoDelete() {
        let fake = FakeKeychain()
        let keychain = fake.keychain()
        #expect(keychain.write("first") && keychain.write("second"))
        #expect(fake.stored() == "second")
        #expect(fake.adds.count == 1, "added once, the first time")
        #expect(fake.deletes == 0, "never deleted to be replaced")
    }

    @Test func aWriteThatCannotReachTheKeychainKeepsTheIdentifierThatWasThere() {
        let fake = FakeKeychain()
        let keychain = fake.keychain()
        #expect(keychain.write("kept"))
        fake.updateStatus = errSecInteractionNotAllowed  // before the first unlock
        #expect(!keychain.write("lost"), "it says it failed")
        #expect(fake.stored() == "kept", "and the old identifier is still there")
        #expect(fake.deletes == 0 && fake.adds.count == 1, "nothing was deleted and nothing was added over it")
    }

    @Test func aFailedAddAfterNoItemLeavesNothingAndDeletesNothing() {
        let fake = FakeKeychain()
        fake.addStatus = errSecInteractionNotAllowed
        #expect(!fake.keychain().write("first"))
        #expect(fake.stored() == nil && fake.deletes == 0)
    }

    @Test func theItemIsAfterFirstUnlockThisDeviceOnlyAndNeverSynchronized() throws {
        let fake = FakeKeychain()
        let keychain = fake.keychain()
        #expect(keychain.write("one") && keychain.write("two"))
        let added = try #require(fake.adds.first)
        #expect(added[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(added[kSecAttrSynchronizable as String] as? Bool == false)
        let updated = try #require(fake.updates.last)
        #expect(updated[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String, "an update keeps the class too")
    }

    @Test func deletingForgetsTheItemAndTheNextWriteAddsAgain() {
        let fake = FakeKeychain()
        let keychain = fake.keychain()
        #expect(keychain.write("one"))
        keychain.delete()
        #expect(fake.stored() == nil && fake.deletes == 1)
        #expect(keychain.write("two") && fake.stored() == "two" && fake.adds.count == 2)
    }

    @Test func theAppsOwnItemKeepsItsServiceAndAccountNames() {
        #expect(SystemAccountKeychain.service == "com.noctis.app.account" && SystemAccountKeychain.account == "appleUserID")
    }
}
