import Foundation

// The words of a locked area (APP_RULES.md R58): one honest line saying exactly what is included, nothing about time running out, nothing about what is being
// missed, nothing about anyone else. Each is true of the app as it is; the comparison ("What Premium includes") is the full list.

public nonisolated enum LockedCopy {
    public struct Card: Equatable, Sendable {
        public var title: String
        public var line: String
    }

    public static let seePremium = "See Premium"

    /// The card for a locked area that has one (at most one on a screen); nil for contexts that open from a lock glyph or a tap.
    public static func card(for context: PaywallContext) -> Card? {
        switch context {
        case .sleepQuality:
            Card(title: "What went into your sleep quality", line: "Premium shows the four factors behind your score and what changed.")
        case .insightsAll:
            Card(title: "Everything NOCTIS found, your records and the full history", line: "Premium shows every insight, your records and your insight history.")
        case .coachQuestions:
            Card(title: CoachQuota.usedUpTitle, line: "\(CoachQuota.usedUpDetail) Premium has no daily limit.")
        case .tonightWindow:
            Card(title: "See why this time and your bedtime window", line: "Premium shows the window around tonight's bedtime and the reasons for it.")
        default:
            nil
        }
    }

    /// Words that press, hurry or shame. None of them appears anywhere a person reads about Premium (a test holds every line to it).
    public static let pressureWords = [
        "limited", "hurry", "last chance", "don't miss", "miss out", "missing out", "act now", "today only", "ends soon", "expires", "% off", "special offer",
        "deal", "offer ends", "countdown", "only a few", "running out", "you're falling behind", "don't you want", "are you sure", "unlock your potential",
    ]

    /// The pressure words in `text`, whole words only ("unlimited" is not "limited").
    public static func pressure(in text: String) -> [String] {
        let lower = text.lowercased()
        return pressureWords.filter { word in
            let escaped = NSRegularExpression.escapedPattern(for: word)
            return lower.range(of: "(?<![a-z])\(escaped)(?![a-z])", options: .regularExpression) != nil
        }
    }
}
