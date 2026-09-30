import Foundation
import NoctisCore
import RecoveryKit

/// One suggested question, and how much the person's own data makes it worth
/// asking.
public struct CoachSuggestion: Sendable, Equatable, Identifiable {
    public let question: CoachQuestion
    /// 0...1: how large the recent change behind it is.
    public let relevance: Double

    public var id: String { question.token }
}

/// Orders the six suggested questions by what changed most recently, and gives
/// "why higher / lower" the direction the data actually moved. No number here
/// is a guess: each comes from a fact an engine wrote, and a question with
/// nothing behind it keeps its place at the end, in the fixed order.
public enum CoachSuggestionRanker {
    /// A change this size (or larger) is as relevant as a change can be.
    public static let recoveryFullPoints = 15.0
    public static let sleepFullMinutes = 60.0
    public static let bedtimeFullMinutes = 60.0
    public static let spreadFullMinutes = 120.0
    /// What a question with no change behind it always has: "When should I
    /// sleep?" and "What should I focus on today?" are never wrong to ask.
    public static let standingRelevance = 0.15
    public static let focusRelevance = 0.3
    /// In the evening, bedtime is what the day is about.
    public static let eveningBedtimeRelevance = 1.0

    /// A recovery difference under this many points is "in line", not higher or lower.
    public static let recoveryThreshold = Double(RecoveryModelV1.trendThreshold)
    /// A sleep difference under this many minutes is "about the same".
    public static let sleepThreshold = TemplateCoachProvider.minorMinutes

    public static func rank(facts: [CoachFact], state: CoachDataState, evening: Bool) -> [CoachSuggestion] {
        func value(_ id: String) -> Double? { facts.first { $0.id == id }?.value }
        func scale(_ delta: Double?, _ full: Double) -> Double { delta.map { min(abs($0) / full, 1) } ?? 0 }
        let usable = state != .noData

        let recoveryDelta = value("recovery.deltaVsUsual")
        let recoveryTrend: CoachTrend? = recoveryDelta.flatMap { $0 <= -recoveryThreshold ? .lower : ($0 >= recoveryThreshold ? .higher : nil) }
        let sleepDelta = value("sleep.deltaVsBaseline")
        let sleepTrend: CoachTrend? = sleepDelta.flatMap { $0 <= -sleepThreshold ? .lower : ($0 >= sleepThreshold ? .higher : nil) }
        let spread = value("consistency.bedtimeVarMin").map { min($0 / spreadFullMinutes, 1) } ?? 0

        let scored: [(CoachQuestion, Double)] = [
            (.recovery(recoveryTrend), scale(recoveryDelta, recoveryFullPoints)),
            (.sleep(sleepTrend), scale(sleepDelta, sleepFullMinutes)),
            (.week, scale(value("week.avgSleepDelta"), sleepFullMinutes)),
            (.bedtime, evening ? eveningBedtimeRelevance : standingRelevance),
            (.consistency, max(scale(value("bedtime.deltaVsUsual"), bedtimeFullMinutes), spread)),
            (.focus, focusRelevance),
        ]
        return scored.enumerated()
            .map { index, entry in (index, CoachSuggestion(question: entry.0, relevance: usable ? entry.1 : 0)) }
            .sorted { lhs, rhs in
                lhs.1.relevance != rhs.1.relevance ? lhs.1.relevance > rhs.1.relevance : lhs.0 < rhs.0
            }
            .map(\.1)
    }
}
