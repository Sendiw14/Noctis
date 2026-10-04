import Foundation
import NightKit

/// The breathing exercise's words (APP_RULES.md R33). Calm and plain. It says what it is and nothing
/// about what it does for anyone's body, mood, anxiety or sleep.
public nonisolated enum BreathingCopy {
    public static let title = "Breathing"
    public static let line = "A slow breathing exercise."
    public static let patternCaption = "PATTERN"
    public static let durationCaption = "HOW LONG"
    public static let begin = "Begin"
    public static let end = "End"
    public static let pause = "Pause"
    public static let resume = "Resume"
    public static let again = "Again"
    public static let finishedTitle = "Finished"
    public static let hapticsTitle = "Gentle haptics"
    public static let hapticsNote = "Soft taps that follow each breath. They follow your iPhone's haptic settings."

    public static func phaseName(_ kind: BreathingPhaseKind) -> String {
        switch kind {
        case .inhale: "Inhale"
        case .hold: "Hold"
        case .exhale: "Exhale"
        }
    }

    /// "Inhale 4 · Hold 2 · Exhale 6", for the chosen pattern.
    public static func summary(_ pattern: BreathingPattern) -> String {
        pattern.phases.map { "\(phaseName($0.kind)) \($0.seconds)" }.joined(separator: " · ")
    }

    /// The same, for VoiceOver: no dots to be read out.
    public static func spokenSummary(_ pattern: BreathingPattern) -> String {
        pattern.phases.map { "\(phaseName($0.kind)) for \($0.seconds)" }.joined(separator: ", ")
    }

    /// "Inhale, 4 seconds": what VoiceOver says when a phase begins.
    public static func announcement(_ kind: BreathingPhaseKind, seconds: Int) -> String {
        "\(phaseName(kind)), \(seconds) \(seconds == 1 ? "second" : "seconds")"
    }

    /// "5 min left" to the nearest minute (a 5 minute Relax is 5:04, and must not say 6), then "90 s left" and
    /// down in the last minute and a half.
    public static func remaining(_ seconds: TimeInterval) -> String {
        let whole = max(Int(seconds.rounded(.up)), 0)
        if whole > 90 { return "\(roundedMinutes(whole)) min left" }
        return "\(whole) s left"
    }

    public static func remainingSpoken(_ seconds: TimeInterval) -> String {
        let whole = max(Int(seconds.rounded(.up)), 0)
        if whole > 90 {
            let count = roundedMinutes(whole)
            return "\(count) \(count == 1 ? "minute" : "minutes") left"
        }
        return "\(whole) \(whole == 1 ? "second" : "seconds") left"
    }

    private static func roundedMinutes(_ seconds: Int) -> Int {
        Int((Double(seconds) / 60).rounded())
    }

    /// The finished line: what was done, with no score.
    public static func finishedLine(pattern: BreathingPattern, minutes: Int) -> String {
        "\(pattern.title) breathing, \(minutes) min."
    }
}
