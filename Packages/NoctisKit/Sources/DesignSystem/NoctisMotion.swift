import SwiftUI

public enum NoctisMotion {
    /// Content settling into its resolved state — data-state swaps, staged
    /// entrances. Critically damped like `snap`, but a touch slower and
    /// calmer: `snap` is for an interactive commit (press, drag release),
    /// `settle` is for content arriving on its own.
    public static let settle = Animation.spring(response: 0.42, dampingFraction: 1.0)
    public static let flow = Animation.spring(response: 0.5, dampingFraction: 0.86)
    public static let snap = Animation.spring(response: 0.28, dampingFraction: 1.0)
    public static let reveal = Animation.spring(response: 0.45, dampingFraction: 0.92)
    /// Reserved for a genuinely gesture-driven, velocity-carrying
    /// interaction (a flick, a drag-to-dismiss) — none exists yet. Do not
    /// reach for this just to give it a call site.
    public static let momentum = Animation.spring(response: 0.4, dampingFraction: 0.8)
    /// Reserved for a slow, ambient NOCTIS moment (Wind Down and similar,
    /// not yet built) — not a general-purpose "pulse." `NoctisLoadingState`'s
    /// existing loading pulse is a different, faster "working" tempo and is
    /// left as it is.
    public static let breath = Animation.easeInOut(duration: 4.0)
    /// A single one-shot reveal (a path drawing itself in, a sheen sweep) —
    /// distinct from `reveal`, which is spring-based for content arriving;
    /// this is a plain eased duration for effects with a literal start and
    /// end rather than a settling motion.
    public static let drawIn = Animation.easeOut(duration: 1.2)

    /// Every gesture-driven or hero transition should route through this so
    /// Reduce Motion swaps springs/slides for a plain cross-fade.
    public static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : animation
    }
}
