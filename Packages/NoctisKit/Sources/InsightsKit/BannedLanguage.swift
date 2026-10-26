import Foundation

/// The words no generated sentence may contain, in one place: the Insights
/// lint (`InsightLanguageTests`) and Coach's safety validator both read it.
/// Matching is on the lowercased text as a substring, so a stem like
/// "diagnos" covers every form of the word.
public enum BannedLanguage {
    /// What Insights never says.
    public static let insights = [
        "cause", "because", "diagnos", "disease", "sick", "insomnia", "apnea", "should", "must", "poor", "bad", "debt", "danger", "warning", "worry",
    ]

    /// What Coach never says: everything above, and the language of medicine,
    /// certainty and blame. "cause" also covers "caused" and "because".
    public static let coach =
        insights + [
            "disorder", "depress", "anxiety", "treatment", "medication", "prescri", "cure", "you have", "healthy", "unhealthy",
            "completely recovered", "definitely", "guarantee", "caused",
        ]

    /// The terms of `list` that `text` contains, in list order.
    public static func hits(in text: String, of list: [String]) -> [String] {
        let lowered = text.lowercased()
        return list.filter { lowered.contains($0) }
    }
}
