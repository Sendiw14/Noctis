import Foundation
import RecoveryKit

/// Screens pushed inside the Home tab's navigation stack.
public nonisolated enum HomeRoute: Sendable, Hashable {
    /// Recovery in detail, zooming out of Home's ring; `focus` scrolls to
    /// that factor's row (a factor capsule was tapped).
    case recoveryDetail(focus: RecoveryFactorKind? = nil)
    /// Profile, from the avatar button ("Coming soon" until built).
    case profile
}
