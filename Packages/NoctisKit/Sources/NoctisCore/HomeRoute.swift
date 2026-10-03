import Foundation
import RecoveryKit

/// Screens pushed inside the Home tab's navigation stack.
public nonisolated enum HomeRoute: Sendable, Hashable {
    /// Recovery in detail, zooming out of Home's ring; `focus` scrolls to
    /// that factor's row (a factor capsule was tapped).
    case recoveryDetail(focus: RecoveryFactorKind? = nil)
    /// One factor's detail, from a factor capsule or a card.
    case recoveryFactor(RecoveryFactorKind, range: RecoveryFactorRange = .fortnight)
    /// Profile, from the avatar button ("Coming soon" until built).
    case profile
    /// Tonight: the bedtime window, why, and the wake alarm.
    case tonight
    /// Wind-down, over Tonight ("Coming soon" until built).
    case windDown(autostart: Bool)
    /// Sleep sounds, over Tonight ("Coming soon" until built).
    case sounds
}
