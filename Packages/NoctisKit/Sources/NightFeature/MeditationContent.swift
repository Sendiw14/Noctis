import Foundation
import NightKit

/// The meditation's words (APP_RULES.md R34). The lines and the category names are in the String
/// Catalog (`Resources/Meditation.xcstrings`, English now); the rest of the screen's few words are here.
/// Calm and plain: nothing about what any of it does for anyone's health, mind or sleep.
public nonisolated enum MeditationCopy {
    public static let title = "Meditation"
    public static let line = "Quiet, timed sessions with soft chimes."
    public static let categoryCaption = "WHAT"
    public static let durationCaption = "HOW LONG"
    public static let soundCaption = "SOUND UNDERNEATH"
    public static let noSound = "None"
    public static let spokenTitle = "Spoken guidance"
    public static let spokenNote = "Read aloud by your iPhone's built-in voice. The pauses follow the schedule."
    public static let begin = "Begin"
    public static let pause = "Pause"
    public static let resume = "Resume"
    public static let end = "End"
    public static let again = "Again"
    public static let finishedTitle = "Finished"

    /// The catalog's text for `key`; the key itself when it is missing, so a missing string shows up in a
    /// test as "meditation.…" rather than as a blank.
    public static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: key, table: "Meditation")
    }

    public static func title(_ category: MeditationCategory) -> String { string(category.titleKey) }
    public static func summary(_ category: MeditationCategory) -> String { string(category.summaryKey) }

    /// The symbol for a category's tile.
    public static func symbol(_ category: MeditationCategory) -> String {
        switch category {
        case .sleep: "moon.zzz"
        case .relax: "leaf"
        case .breathing: "wind"
        case .bodyScan: "figure.mind.and.body"
        case .quietMind: "circle.dotted"
        }
    }

    /// "Body scan, 10 min.": what was done, with no score.
    public static func finishedLine(category: MeditationCategory, minutes: Int) -> String {
        "\(title(category)), \(minutes) min."
    }
}
