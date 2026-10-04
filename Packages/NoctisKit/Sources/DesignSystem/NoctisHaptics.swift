#if canImport(UIKit)
import UIKit
#endif
#if canImport(CoreHaptics)
import CoreHaptics
#endif

public enum NoctisHaptics {
    /// The app's own haptics (a tap, a confirmation, a snapped value) on or off, from Settings. It can only
    /// quiet them: the generators below already follow the system's haptics setting, and nothing here
    /// ever plays one the system has turned off.
    public static var isEnabled = true

    public static func selection() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    public static func soft() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    public static func light() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    public static func medium() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    public static func success() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    public static func warning() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    // MARK: Onboarding scaffold additions
    // Named for their call site rather than their underlying generator, so
    // the intent reads at the point of use — several of these share an
    // underlying style with the tokens above and that's fine.

    /// A light selection tick — the moon/sun traveling along the step
    /// progress line, a snapped value.
    public static func selectionTick() {
        selection()
    }

    /// A soft confirmation — a card settling, a reveal completing.
    public static func softImpact() {
        soft()
    }

    /// A light tick specifically for an interactive "snap" moment (drag
    /// releasing onto a value) — kept distinct from `selectionTick` at the
    /// call site even though today it shares an implementation.
    public static func snapLight() {
        light()
    }

    /// An hourly boundary crossed while scrubbing a time control.
    public static func hourTick() {
        medium()
    }

    /// Hit the edge of a valid range (minimum/maximum clamp).
    public static func limit() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
    }

    /// A short crescendo for a genuine "arrival" moment (onboarding
    /// completing) — CoreHaptics, not the simpler generators above, because
    /// only CHHapticEngine can ramp intensity over time. Safe everywhere:
    /// the simulator and older hardware report `supportsHaptics == false`,
    /// so this silently no-ops there rather than crashing, and engine
    /// creation/start errors are caught rather than thrown.
    public static func swell() {
        guard isEnabled else { return }
        #if canImport(CoreHaptics)
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            try engine.start()
            let intensityCurve = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0.15),
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0.6, value: 1.0),
                ],
                relativeTime: 0
            )
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)],
                relativeTime: 0,
                duration: 0.6
            )
            let pattern = try CHHapticPattern(events: [event], parameterCurves: [intensityCurve])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            engine.notifyWhenPlayersFinished { _ in .stopEngine }
        } catch {
            // Best-effort only — a missed haptic is never worth surfacing.
        }
        #endif
    }
}
