import Foundation
import RecoveryKit
import SleepKit

/// A night or a week that stands out against your own history: the longest
/// night in a month, your most consistent week yet, your best deep sleep in
/// 30 nights. Only ever true: each needs enough nights to compare with,
/// and the night must beat every other one strictly (a tie is not a record).
public enum SleepHighlight: Sendable, Equatable, Hashable {
    /// The longest time asleep among the last 30 nights.
    case longestNight
    /// The most regular bedtime over 7 nights of any week so far.
    case mostConsistentWeek
    /// The most deep sleep among the last 30 nights.
    case bestDeepSleep
}

public enum SleepHighlightsEngine {
    /// Nights recorded in the 30-night window before a night-based
    /// highlight can be claimed.
    public static let minimumWindowNights = 14
    /// Earlier weeks that must have a value before a week can be the most
    /// consistent yet: two weeks of others to beat.
    public static let minimumEarlierWeeks = 8
    public static let windowNights = 30
    public static let weekNights = 7

    /// The highlights `night` earns, from every main night's metrics.
    public static func highlights(metrics: [SleepMetrics], endingAt night: SleepNightKey) -> [SleepHighlight] {
        var result: [SleepHighlight] = []
        let byNight = Dictionary(metrics.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        guard let tonight = byNight[night] else { return [] }

        let first = night.adding(days: -(windowNights - 1))
        let window = metrics.filter { $0.night >= first && $0.night <= night }

        // Longest night: strictly more asleep than every other night in the window.
        if window.count >= minimumWindowNights,
           window.allSatisfy({ $0.night == night || $0.asleepMinutes < tonight.asleepMinutes }) {
            result.append(.longestNight)
        }

        // Best deep sleep: among the nights that have stages, strictly the most.
        if let deep = tonight.stages?.deep {
            let staged = window.compactMap { entry in entry.stages.map { (entry.night, $0.deep) } }
            if staged.count >= minimumWindowNights, staged.allSatisfy({ $0.0 == night || $0.1 < deep }) {
                result.append(.bestDeepSleep)
            }
        }

        if mostConsistentWeek(metrics: metrics, endingAt: night) { result.append(.mostConsistentWeek) }
        return result
    }

    /// Whether the 7 nights ending at `night` have a steadier bedtime (a
    /// lower sample standard deviation) than the 7 nights ending at each
    /// earlier night that has a value, needing 5 recorded nights in a week
    /// like every baseline.
    public static func mostConsistentWeek(metrics: [SleepMetrics], endingAt night: SleepNightKey) -> Bool {
        guard let current = bedtimeSpread(metrics: metrics, endingAt: night) else { return false }
        let earliest = metrics.map(\.night).min() ?? night
        var earlier: [Double] = []
        var end = night.adding(days: -1)
        while end >= earliest.adding(days: weekNights - 1) {
            if let spread = bedtimeSpread(metrics: metrics, endingAt: end) { earlier.append(spread) }
            end = end.adding(days: -1)
        }
        return earlier.count >= minimumEarlierWeeks && earlier.allSatisfy { current < $0 }
    }

    /// The bedtime spread (SD, minutes) over the week ending at `night`.
    public static func bedtimeSpread(metrics: [SleepMetrics], endingAt night: SleepNightKey) -> Double? {
        let first = night.adding(days: -(weekNights - 1))
        let bedtimes = metrics.filter { $0.night >= first && $0.night <= night }.map(\.bedtimeMinutes)
        return BaselineEngine.baseline(bedtimes)?.standardDeviation
    }
}
