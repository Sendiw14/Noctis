import Foundation
import RecoveryKit
import SleepKit

public struct SleepTimingShift: Sendable, Equatable, Codable {
    /// The last 7 nights' median minus the median of the 14 nights before
    /// them, in minutes: positive is later.
    public let bedtimeMinutes: Double
    public let wakeMinutes: Double

    public init(bedtimeMinutes: Double, wakeMinutes: Double) {
        self.bedtimeMinutes = bedtimeMinutes
        self.wakeMinutes = wakeMinutes
    }
}

/// A range of clock times built from your own nights, in minutes after noon.
public struct SleepTimingRange: Sendable, Equatable, Codable {
    public let bedtime: ClosedRange<Double>
    public let wake: ClosedRange<Double>

    public init(bedtime: ClosedRange<Double>, wake: ClosedRange<Double>) {
        self.bedtime = bedtime
        self.wake = wake
    }
}

public struct SleepTimingResult: Sendable, Equatable, Codable {
    /// Medians over the last 14 nights, in minutes after noon; nil under
    /// 5 recorded nights.
    public let typicalBedtime: Double?
    public let typicalWake: Double?
    /// Nights in that 14-night window with sleep recorded.
    public let nights: Int
    public var typicalMidpoint: Double? {
        guard let typicalBedtime, let typicalWake else { return nil }
        return (typicalBedtime + typicalWake) / 2
    }
    /// The recent 7 nights against the 14 before them; nil unless both
    /// windows have 5 recorded nights.
    public let recentShift: SleepTimingShift?
    /// Only with 14 or more recorded nights in the last 30: the middle
    /// half of your own bedtimes and wake times (never narrower than 30
    /// minutes), as a suggested range. It describes your pattern; it isn't
    /// a target.
    public let suggested: SleepTimingRange?
    public let night: SleepNightKey

    public init(typicalBedtime: Double?, typicalWake: Double?, nights: Int, recentShift: SleepTimingShift?, suggested: SleepTimingRange?, night: SleepNightKey)
    {
        self.typicalBedtime = typicalBedtime
        self.typicalWake = typicalWake
        self.nights = nights
        self.recentShift = recentShift
        self.suggested = suggested
        self.night = night
    }
}

/// Typical bedtime and wake time (medians), the recent shift and, with
/// enough nights, a suggested range.
public enum SleepTimingEngine {
    public static let typicalWindowNights = 14
    public static let recentNights = 7
    public static let priorNights = 14
    public static let suggestionWindowNights = 30
    public static let suggestionMinimumNights = 14
    /// The suggested range is at least this wide (minutes).
    public static let minimumRangeWidth: Double = 30
    public static let minimumNights = BaselineEngine.minimumNights

    public static func timing(history: [SleepSession], endingAt night: SleepNightKey? = nil) -> SleepTimingResult? {
        let mains = history.filter { $0.kind == .main }
        guard let end = night ?? mains.map(\.night).max() else { return nil }
        func metrics(_ from: Int, _ to: Int) -> [SleepMetrics] {
            // Nights `to`...`from` days before `end`, inclusive.
            let first = end.adding(days: -from)
            let last = end.adding(days: -to)
            return mains.filter { $0.night >= first && $0.night <= last }.map(SleepMetricsEngine.metrics(for:))
        }

        // "Usual" is the BaselineEngine's: the mean of the 14 nights before `end`, never the night itself, so every surface that says "your usual
        // bedtime" (Home, Sleep, Coach, Insights, Profile, Reviews) prints the same time.
        let typical = metrics(typicalWindowNights, 1)
        let bedtime = BaselineEngine.baseline(typical.map(\.bedtimeMinutes))?.value
        let wake = BaselineEngine.baseline(typical.map(\.wakeMinutes))?.value

        var shift: SleepTimingShift?
        let recent = metrics(recentNights - 1, 0)
        let prior = metrics(recentNights + priorNights - 1, recentNights)
        if recent.count >= minimumNights, prior.count >= minimumNights,
            let recentBed = median(recent.map(\.bedtimeMinutes)), let priorBed = median(prior.map(\.bedtimeMinutes)),
            let recentWake = median(recent.map(\.wakeMinutes)), let priorWake = median(prior.map(\.wakeMinutes))
        {
            shift = SleepTimingShift(bedtimeMinutes: recentBed - priorBed, wakeMinutes: recentWake - priorWake)
        }

        var suggested: SleepTimingRange?
        let month = metrics(suggestionWindowNights - 1, 0)
        if month.count >= suggestionMinimumNights,
            let bed = middleHalf(month.map(\.bedtimeMinutes)), let wakeRange = middleHalf(month.map(\.wakeMinutes))
        {
            suggested = SleepTimingRange(bedtime: bed, wake: wakeRange)
        }

        return SleepTimingResult(typicalBedtime: bedtime, typicalWake: wake, nights: typical.count, recentShift: shift, suggested: suggested, night: end)
    }

    /// The median of `values` (the mean of the two middle ones when even).
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// The 25th to 75th percentile (linear interpolation), widened around
    /// its middle to at least `minimumRangeWidth`.
    static func middleHalf(_ values: [Double]) -> ClosedRange<Double>? {
        guard let low = percentile(values, 0.25), let high = percentile(values, 0.75) else { return nil }
        let middle = (low + high) / 2
        let half = max((high - low) / 2, minimumRangeWidth / 2)
        return (middle - half)...(middle + half)
    }

    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }
}
