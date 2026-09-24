import Foundation

/// Screens pushed inside the Home tab's navigation stack.
public nonisolated enum HomeRoute: String, Sendable, Hashable, CaseIterable {
    /// Recovery in detail, zooming out of Home's ring.
    case recoveryDetail
    /// Profile, from the avatar button ("Coming soon" until built).
    case profile
}
