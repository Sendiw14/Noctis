import Foundation

/// The Journal as plain values, for "Export my data" and nothing else (APP_RULES.md R41): what the person wrote, in a file they asked
/// for. It reads through the store like the Reflect screens do; it logs, counts and sends nothing.
public enum JournalExport {
    /// One object per entry, newest first: its date and what was written.
    @MainActor
    public static func object(from store: any JournalStoring) throws -> [[String: Any]] {
        try store.entries().map { entry in
            var object: [String: Any] = ["date": ISO8601DateFormatter().string(from: entry.date), "text": entry.text]
            if let energy = entry.energy { object["energy"] = energy }
            if let mood = entry.mood { object["mood"] = mood }
            if let focus = entry.focus { object["focus"] = focus }
            return object
        }
    }
}
