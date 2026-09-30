import Foundation

/// Every pattern and every sentence Coach says on its own, read from the
/// String Catalog (`Resources/Coach.xcstrings`, English now).
public enum CoachCopy {
    /// The copy for `key`; the key itself when it is missing, so a missing
    /// string shows up in a test as "coach.…" rather than as a blank.
    public static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: key, table: "Coach")
    }
}
