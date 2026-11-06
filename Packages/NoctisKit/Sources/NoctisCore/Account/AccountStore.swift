import AuthenticationServices
import Foundation
import Security

// Sign in with Apple, optional and local (APP_RULES.md R69). The only thing kept is Apple's opaque user identifier, in the Keychain of this iPhone;
// nothing is sent anywhere, and no feature, screen or limit depends on being signed in.

/// What Apple's sign-in handed back, reduced to what NOCTIS may use: the user identifier and the given name (never an email, never a token).
public nonisolated struct AppleSignInCredential: Sendable, Equatable {
    public let userID: String
    public let givenName: String?

    public init(userID: String, givenName: String?) {
        self.userID = userID
        self.givenName = givenName
    }
}

public nonisolated enum AppleCredentialState: Sendable, Equatable {
    case authorized
    case revoked
    case notFound
    case transferred
}

public nonisolated enum AccountState: Sendable, Equatable {
    case signedOut
    case signedIn(userID: String)

    public var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}

/// Where the user identifier is kept: the Keychain in the app, a dictionary in tests.
public nonisolated protocol AccountKeychain: Sendable {
    func read() -> String?
    func write(_ userID: String) -> Bool
    func delete()
    /// Whether the item is there, is not, or cannot be asked about now (the iPhone has not been unlocked since it started): "nothing found" and "cannot look" must not
    /// be taken for each other (S1B-R-16).
    func lookup() -> KeychainLookup
}

public nonisolated enum KeychainLookup: Sendable, Equatable {
    case found
    case notFound
    case unavailable
}

nonisolated extension AccountKeychain {
    /// For a keychain that is always answerable (memory, tests).
    public func lookup() -> KeychainLookup { read() == nil ? .notFound : .found }
}

/// Asks Apple whether the identifier is still good: Apple's provider in the app, a fake in tests.
public nonisolated protocol AppleCredentialChecking: Sendable {
    func state(for userID: String) async -> AppleCredentialState
}

/// What a tap on "Continue with Apple" came to.
public nonisolated enum SignInOutcome: Sendable, Equatable {
    /// Signed in; `prefill` is the name to offer in the name step (nil: leave the field as it is).
    case signedIn(prefill: String?)
    /// The person closed Apple's sheet: nothing is said.
    case cancelled
    case failed
}

@MainActor @Observable
public final class AccountStore {
    public private(set) var state: AccountState

    private let keychain: any AccountKeychain
    private let checker: any AppleCredentialChecking

    public init(keychain: any AccountKeychain = SystemAccountKeychain(), checker: any AppleCredentialChecking = SystemAppleCredentialChecker()) {
        self.keychain = keychain
        self.checker = checker
        state = keychain.read().map { .signedIn(userID: $0) } ?? .signedOut
    }

    /// The name to offer, by the one rule: a name the person already has is never replaced; otherwise Apple's given name, trimmed; otherwise nothing.
    public nonisolated static func prefilledName(existing: String, given: String?) -> String? {
        guard existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let name = given?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    /// A result from Apple's sheet. `existingName` is the profile's name today.
    @discardableResult
    public func complete(_ result: Result<AppleSignInCredential, any Error>, existingName: String) -> SignInOutcome {
        switch result {
        case .success(let credential):
            guard keychain.write(credential.userID) else { return .failed }
            state = .signedIn(userID: credential.userID)
            return .signedIn(prefill: Self.prefilledName(existing: existingName, given: credential.givenName))
        case .failure(let error):
            return Self.isCancellation(error) ? .cancelled : .failed
        }
    }

    public nonisolated static func isCancellation(_ error: any Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }

    /// At launch: Apple says whether the identifier is still good. Revoked or unknown: signed out here, every local thing kept. Never blocks.
    public func refresh() async {
        guard case .signedIn(let userID) = state else { return }
        switch await checker.state(for: userID) {
        case .authorized, .transferred: break
        case .revoked, .notFound: signOut()
        }
    }

    /// Apple's `credentialRevokedNotification`.
    public func credentialRevoked() { signOut() }

    /// Forgets the identifier. Local data stays.
    public func signOut() {
        keychain.delete()
        state = .signedOut
    }

    /// Forgets the identifier as part of deleting everything (the data itself is deleted by the delete-all path).
    public func deleteAccount() { signOut() }
}

// MARK: - The system's

/// The Keychain calls that change the item, so a test can make them fail.
nonisolated struct KeychainCalls: Sendable {
    var update: @Sendable (_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
    var add: @Sendable (_ attributes: [String: Any]) -> OSStatus
    var delete: @Sendable (_ query: [String: Any]) -> OSStatus

    static let system = KeychainCalls(
        update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
        add: { SecItemAdd($0 as CFDictionary, nil) },
        delete: { SecItemDelete($0 as CFDictionary) }
    )
}

/// The Keychain item: a generic password under NOCTIS's service, readable after the first unlock, never leaving this iPhone (no iCloud sync, not in
/// a backup restored to another device).
public nonisolated struct SystemAccountKeychain: AccountKeychain {
    public static let service = "com.noctis.app.account"
    public static let account = "appleUserID"

    private let service: String
    private let account: String
    private let calls: KeychainCalls

    public init() { self.init(service: Self.service, account: Self.account, calls: .system) }

    /// Other Keychain calls, for tests that make them fail (the real Keychain answers no one outside the app).
    init(service: String, account: String, calls: KeychainCalls) {
        self.service = service
        self.account = account
        self.calls = calls
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func read() -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            query.merging([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]) { $1 } as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replaces the item in place, and adds it when there is none. It never deletes first: a write that fails (the iPhone locked before its first unlock, say) leaves
    /// the identifier that was there, where delete-then-add lost it.
    public func write(_ userID: String) -> Bool {
        let value = Data(userID.utf8)
        let accessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let updated = calls.update(query, [kSecValueData as String: value, kSecAttrAccessible as String: accessible])
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        let attributes: [String: Any] = [kSecValueData as String: value, kSecAttrAccessible as String: accessible, kSecAttrSynchronizable as String: false]
        return calls.add(query.merging(attributes) { $1 }) == errSecSuccess
    }

    public func delete() { _ = calls.delete(query) }

    public func lookup() -> KeychainLookup {
        let status = SecItemCopyMatching(query.merging([kSecMatchLimit as String: kSecMatchLimitOne]) { $1 } as CFDictionary, nil)
        switch status {
        case errSecSuccess: return .found
        case errSecItemNotFound: return .notFound
        default: return .unavailable  // for example errSecInteractionNotAllowed, before the first unlock
        }
    }

    /// How many bytes the item holds (for the Privacy Center), 0 when there is none.
    public var byteCount: Int { read()?.utf8.count ?? 0 }
}

public nonisolated struct SystemAppleCredentialChecker: AppleCredentialChecking {
    public init() {}

    public func state(for userID: String) async -> AppleCredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                switch state {
                case .authorized: continuation.resume(returning: .authorized)
                case .revoked: continuation.resume(returning: .revoked)
                case .notFound: continuation.resume(returning: .notFound)
                case .transferred: continuation.resume(returning: .transferred)
                @unknown default: continuation.resume(returning: .authorized)
                }
            }
        }
    }
}

extension AppleSignInCredential {
    /// From Apple's authorization; nil if it is not an Apple ID credential.
    public init?(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return nil }
        self.init(userID: credential.user, givenName: credential.fullName?.givenName)
    }
}

/// A keychain that lives in memory: the tests' (with a fake checker), and the DEBUG launch flag `-mockAppleAccount signedIn`'s, so the signed-in screens can
/// be seen on a simulator with no Apple ID. It never touches the system Keychain.
public final class MemoryAccountKeychain: AccountKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var userID: String?

    public init(userID: String? = nil) { self.userID = userID }

    public func read() -> String? { lock.withLock { userID } }
    public func write(_ userID: String) -> Bool {
        lock.withLock { self.userID = userID }
        return true
    }
    public func delete() { lock.withLock { userID = nil } }
}

/// Answers the same for every identifier.
public nonisolated struct FixedCredentialChecker: AppleCredentialChecking {
    public let answer: AppleCredentialState
    public init(_ answer: AppleCredentialState = .authorized) { self.answer = answer }
    public func state(for userID: String) async -> AppleCredentialState { answer }
}
