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

    /// Selection, focus and dimming that follow a finger (a bar, a lane, a
    /// scrub): critically damped and quick. Being a spring, it retargets
    /// from wherever it is when the next change lands, so a fast drag never
    /// waits for the last change to finish.
    public static let select = Animation.spring(response: 0.2, dampingFraction: 1.0)
    /// Content fading in or out where it stands (a pill, an overlay, the
    /// skeleton into content): the same critically damped spring, calmer.
    public static let fade = Animation.spring(response: 0.3, dampingFraction: 1.0)
    /// A one-shot reveal with a literal start and end (a ring drawing, the
    /// dusk lifting) as a spring with no bounce, taking about `duration`
    /// to settle. Unlike an eased duration it can be interrupted and
    /// retargeted mid-flight without a jump.
    public static func draw(_ duration: Double) -> Animation {
        .spring(duration: duration, bounce: 0)
    }
    /// The skeleton's slow pulse while data loads: ambient, and removed the
    /// moment content arrives, so nothing needs to interrupt it.
    public static let pulse = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)

    /// Every gesture-driven or hero transition should route through this so
    /// Reduce Motion swaps springs/slides for a plain cross-fade.
    public static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }

    /// What Reduce Motion gets in place of any movement: a 0.2s fade.
    public static let reduced = Animation.easeInOut(duration: 0.2)
}
