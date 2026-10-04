import Foundation
import RecoveryKit

/// Screens pushed inside the Home tab's navigation stack.
public nonisolated enum HomeRoute: Sendable, Hashable {
    /// Recovery in detail, zooming out of Home's ring; `focus` scrolls to
    /// that factor's row (a factor capsule was tapped).
    case recoveryDetail(focus: RecoveryFactorKind? = nil)
    /// One factor's detail, from a factor capsule or a card.
    case recoveryFactor(RecoveryFactorKind, range: RecoveryFactorRange = .fortnight)
    /// Profile, from the avatar button.
    case profile
    /// Settings, from Profile's gear (the list), or one of its pages.
    case settings(SettingsPage)
    /// Tonight: the bedtime window, why, and the wake alarm.
    case tonight
    /// The wind-down session: `autostart` begins it as it opens, otherwise it opens at the pre-start state.
    case windDown(autostart: Bool)
    /// Sleep sounds, over Tonight.
    case sounds
}
