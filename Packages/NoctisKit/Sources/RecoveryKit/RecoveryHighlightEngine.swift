import Foundation
import SleepKit

/// A score that stands out against your own history. Only ever true: it
/// needs enough scored days to compare with, and today's score must beat
/// every other day in the window strictly (a tie is not a record).
public enum RecoveryHighlight: Sendable, Equatable, Hashable {
    /// Today's score is the highest of the last 30 days.
    case highestIn30Days
}

public enum RecoveryHighlightEngine {
    /// Scored days in the 30-day window before a score can be claimed.
    public static let minimumScoredDays = 14
    public static let windowDays = 30

    /// The highlight the newest day of `history` earns, if any. `history`
    /// is the 30-night history: its last day must be the one scored.
    public static func highlight(days: [RecoveryHistoryDay]) -> RecoveryHighlight? {
        guard let today = days.last, let score = today.score?.score else { return nil }
        let window = days.suffix(windowDays).compactMap(\.score)
        guard window.count >= minimumScoredDays else { return nil }
        let others = window.filter { $0.night != today.night }
        return others.allSatisfy { $0.score < score } ? .highestIn30Days : nil
    }
}
