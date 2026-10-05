import Foundation
import SoundCatalog

// Which sleep sounds a plan includes (APP_RULES.md R57, R59, R62): Brown noise, Rain and Ocean are free; Wind, Fireplace and Ambient are Premium. The one list: the Sounds
// screen, the player's guard, Siri, Shortcuts and Control Center all ask it, and the words an intent speaks are made from it. It depends on the sound names alone (a leaf
// with no audio), so an extension can link it.

public nonisolated enum SoundAccess {
    /// The free sounds.
    public static let freeKinds: [SoundKind] = [.brown, .rain, .ocean]

    /// The order Siri says them in: "Rain, Brown noise and Ocean". The same three sounds as `freeKinds` (a test holds the two together).
    public static let spokenFreeOrder: [SoundKind] = [.rain, .brown, .ocean]

    /// The sound Siri and the controls fall back to when the last one played is no longer included in the plan.
    public static let fallback: SoundKind = .brown

    /// The sounds of `tier`: the free ones, or all six with Premium.
    public static func kinds(for tier: Tier) -> [SoundKind] {
        tier == .premium ? SoundKind.allCases : SoundKind.allCases.filter { freeKinds.contains($0) }
    }

    public static func isIncluded(_ kind: SoundKind, in tier: Tier) -> Bool {
        kinds(for: tier).contains(kind)
    }
}
