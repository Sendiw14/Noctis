import AuthenticationServices
import Foundation
import Testing

@testable import NoctisCore

// Sign in with Apple, optional and local (APP_RULES.md R69). A fake keychain and a fake credential checker stand in for the system's, so every outcome is
// held without an Apple ID.

private struct Boom: Error {}

private final class SpyChecker: AppleCredentialChecking, @unchecked Sendable {
    var answer: AppleCredentialState
    private(set) var asked: [String] = []
    init(_ answer: AppleCredentialState) { self.answer = answer }
    func state(for userID: String) async -> AppleCredentialState {
        asked.append(userID)
        return answer
    }
}

@MainActor
struct AccountStoreTests {
    private func store(keychain: MemoryAccountKeychain = MemoryAccountKeychain(), checker: any AppleCredentialChecking = FixedCredentialChecker()) -> AccountStore {
        AccountStore(keychain: keychain, checker: checker)
    }

    @Test func aFreshStoreIsSignedOut() {
        #expect(store().state == .signedOut)
        #expect(!store().state.isSignedIn)
    }

    @Test func signingInKeepsTheIdentifierInTheKeychainAndOffersTheGivenName() {
        let keychain = MemoryAccountKeychain()
        let account = store(keychain: keychain)
        let outcome = account.complete(.success(AppleSignInCredential(userID: "001.abc", givenName: "Sendiw")), existingName: "")
        #expect(outcome == .signedIn(prefill: "Sendiw"))
        #expect(account.state == .signedIn(userID: "001.abc"))
        #expect(keychain.read() == "001.abc", "the identifier is in the keychain, and nowhere else")
    }

    @Test func aStoreStartedLaterReadsTheSameIdentifierBack() {
        let keychain = MemoryAccountKeychain(userID: "001.abc")
        #expect(store(keychain: keychain).state == .signedIn(userID: "001.abc"))
    }

    @Test func cancellingSaysNothingAndChangesNothing() {
        let account = store()
        let outcome = account.complete(.failure(ASAuthorizationError(.canceled)), existingName: "")
        #expect(outcome == .cancelled)
        #expect(account.state == .signedOut)
    }

    @Test func anyOtherErrorIsAFailureAndLeavesTheStoreSignedOut() {
        let account = store()
        #expect(account.complete(.failure(ASAuthorizationError(.failed)), existingName: "") == .failed)
        #expect(account.complete(.failure(Boom()), existingName: "") == .failed)
        #expect(account.state == .signedOut)
    }

    @Test func aKeychainThatCannotBeWrittenIsAFailureNotASignIn() {
        final class Refusing: AccountKeychain, @unchecked Sendable {
            func read() -> String? { nil }
            func write(_ userID: String) -> Bool { false }
            func delete() {}
        }
        let account = AccountStore(keychain: Refusing(), checker: FixedCredentialChecker())
        #expect(account.complete(.success(AppleSignInCredential(userID: "x", givenName: nil)), existingName: "") == .failed)
        #expect(account.state == .signedOut)
    }

    @Test(arguments: [AppleCredentialState.revoked, .notFound])
    func aRevokedOrUnknownCredentialSignsOutAtLaunchAndKeepsEverythingLocal(answer: AppleCredentialState) async {
        let keychain = MemoryAccountKeychain(userID: "001.abc")
        let checker = SpyChecker(answer)
        let account = store(keychain: keychain, checker: checker)
        await account.refresh()
        #expect(checker.asked == ["001.abc"])
        #expect(account.state == .signedOut)
        #expect(keychain.read() == nil)
    }

    @Test(arguments: [AppleCredentialState.authorized, .transferred])
    func aGoodCredentialStaysSignedIn(answer: AppleCredentialState) async {
        let account = store(keychain: MemoryAccountKeychain(userID: "001.abc"), checker: SpyChecker(answer))
        await account.refresh()
        #expect(account.state == .signedIn(userID: "001.abc"))
    }

    @Test func signedOutNeverAsksApple() async {
        let checker = SpyChecker(.revoked)
        await store(checker: checker).refresh()
        #expect(checker.asked.isEmpty)
    }

    @Test func theRevokedNotificationSignsOut() {
        let account = store(keychain: MemoryAccountKeychain(userID: "001.abc"))
        account.credentialRevoked()
        #expect(account.state == .signedOut)
    }

    @Test func signingOutForgetsTheIdentifier() {
        let keychain = MemoryAccountKeychain(userID: "001.abc")
        let account = store(keychain: keychain)
        account.signOut()
        #expect(account.state == .signedOut && keychain.read() == nil)
    }

    @Test func deletingTheAccountWipesTheKeychainItem() {
        let keychain = MemoryAccountKeychain(userID: "001.abc")
        let account = store(keychain: keychain)
        account.deleteAccount()
        #expect(keychain.read() == nil && account.state == .signedOut)
    }

    // MARK: The name rule

    @Test func aNameThatIsAlreadyThereIsNeverReplaced() {
        #expect(AccountStore.prefilledName(existing: "Sam", given: "Sendiw") == nil)
    }

    @Test func anEmptyOrBlankNameTakesApplesGivenNameTrimmed() {
        #expect(AccountStore.prefilledName(existing: "", given: " Sendiw ") == "Sendiw")
        #expect(AccountStore.prefilledName(existing: "   ", given: "Sendiw") == "Sendiw")
    }

    @Test func whenAppleGivesNoNameTheFieldIsLeftAlone() {
        #expect(AccountStore.prefilledName(existing: "", given: nil) == nil)
        #expect(AccountStore.prefilledName(existing: "", given: "  ") == nil)
        let account = store()
        #expect(account.complete(.success(AppleSignInCredential(userID: "u", givenName: nil)), existingName: "") == .signedIn(prefill: nil), "a returning user: no name comes back")
    }

    @Test func aSignInOverAnExistingNameOffersNothing() {
        let account = store()
        #expect(account.complete(.success(AppleSignInCredential(userID: "u", givenName: "Sendiw")), existingName: "Sam") == .signedIn(prefill: nil))
    }
}
