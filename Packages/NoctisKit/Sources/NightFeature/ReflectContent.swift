import Foundation
import NoctisCore
import JournalKit

/// Reflect's and the Journal's words (APP_RULES.md R35). Plain and kind: everything is optional, nothing is
/// counted, scored or remembered against anyone, and nothing is said about what a day "should" have felt like.
public nonisolated enum ReflectCopy {
    public static let title = "Reflect"
    public static let line = "How did today feel? Everything here is optional."
    public static let low = "Low"
    public static let high = "High"
    public static let notePrompt = "Anything you want to note"
    public static let save = "Save"
    public static let skip = "Skip"
    public static let journal = "Journal"
    public static let newEntry = "New entry"
    public static let saved = "Saved"
    public static let notSet = "Not set"
    public static let scaleHint = "Swipe up or down to change it, from low to high."
    public static let clear = "Clear"

    /// From the data inventory (APP_RULES.md R41).
    public static var privacyLine: String { PrivacyStatements.journalLine(.shared) ?? "" }
    public static let emptyTitle = "No entries yet."
    public static let emptyLine = "What you save from Reflect appears here."
    public static let unavailable = "The journal can't be opened right now. Try again once your iPhone is unlocked."
    public static let delete = "Delete"
    public static let deleteAll = "Delete all entries"
    public static let deleteAllTitle = "Delete all journal entries?"
    public static let deleteAllMessage = "This deletes every entry you have written here, from this iPhone. It can't be undone. Your sleep data and the rest of NOCTIS are not affected."
    public static let cancel = "Cancel"

    /// "3 of 5", or "Not set".
    public static func scaleValue(_ value: Int?) -> String {
        value.map { "\($0) of \(JournalDraft.valueRange.upperBound)" } ?? notSet
    }

    /// "Energy 3, Mood 4": the values that were set, for a row in the list.
    public static func valuesLine(_ entry: JournalEntrySnapshot) -> String? {
        let parts = entry.values.map { "\($0.measure.title) \($0.value)" }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The same for VoiceOver: "Energy 3 of 5, Mood 4 of 5".
    public static func spokenValuesLine(_ entry: JournalEntrySnapshot) -> String? {
        let parts = entry.values.map { "\($0.measure.title) \(scaleValue($0.value))" }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
