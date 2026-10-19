import Foundation

/// Every fact id `CoachContextBuilder` can produce, in one place: the only
/// numbers Coach may refer to, and the only ones a remote request may carry.
public enum CoachFactCatalog {
    /// Ids the builder writes as they are.
    public static let ids: Set<String> = [
        "recovery.score", "recovery.usual", "recovery.deltaVsUsual",
        "hrv.today", "hrv.baseline", "rhr.today", "rhr.baseline",
        "sleep.duration", "sleep.baseline", "sleep.deltaVsBaseline", "sleep.quality", "sleep.qualityUsual", "sleep.need", "sleep.balance",
        "deep.share", "deep.usual", "rem.share", "rem.usual",
        "bedtime.last", "bedtime.usual", "bedtime.deltaVsUsual", "bedtime.suggested", "wake.typical", "wake.usual",
        "week.avgSleep", "week.avgSleepDelta", "week.avgRecovery", "week.recoveryTrend",
        "consistency.bedtimeVarMin", "consistency.toleranceMin",
        "history.nights",
    ]

    /// An insight's numbers: "insight.<type>.<name>".
    public static let insightPrefix = "insight."

    public static func allows(_ id: String) -> Bool {
        ids.contains(id) || (id.hasPrefix(insightPrefix) && id.dropFirst(insightPrefix.count).split(separator: ".").count >= 2)
    }
}
