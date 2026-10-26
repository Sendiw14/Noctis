import Foundation
import RecoveryKit
import SleepKit

/// How regular your sleep was over one window of nights.
public struct ConsistencyWindow: Sendable, Equatable, Codable {
    /// The window's length in nights: 7, 14 or 30.
    public let days: Int
    /// Nights in the window with sleep recorded.
    public let nights: Int
    /// Sample standard deviations (n − 1), in minutes.
    public let bedtimeSD: Double
    public let wakeSD: Double
    public let durationSD: Double
    /// Means over the window, in minutes after noon for clock times.
    public let bedtimeMean: Double
    public let wakeMean: Double
    /// The mean sleep midpoint: halfway between bedtime and waking.
    public let midpointMinutes: Double

    public init(days: Int, nights: Int, bedtimeSD: Double, wakeSD: Double, durationSD: Double, bedtimeMean: Double, wakeMean: Double, midpointMinutes: Double) {
        self.days = days
        self.nights = nights
        self.bedtimeSD = bedtimeSD
        self.wakeSD = wakeSD
        self.durationSD = durationSD
        self.bedtimeMean = bedtimeMean
        self.wakeMean = wakeMean
        self.midpointMinutes = midpointMinutes
    }
}

public struct ConsistencyResult: Sendable, Equatable, Codable {
    /// The 7-, 14- and 30-night windows that have enough nights, in that
    /// order; a window with fewer than 5 recorded nights is left out.
    public let windows: [ConsistencyWindow]
    public let night: SleepNightKey
    /// The midpoint of the night the windows end on.
    public let lastMidpointMinutes: Double?

    public init(windows: [ConsistencyWindow], night: SleepNightKey, lastMidpointMinutes: Double?) {
        self.windows = windows
        self.night = night
        self.lastMidpointMinutes = lastMidpointMinutes
    }

    public func window(days: Int) -> ConsistencyWindow? {
        windows.first { $0.days == days }
    }
}

/// Bedtime, wake time and duration spread over 7, 14 and 30 nights, plus
/// the sleep midpoint. Windows end on the newest night (inclusive) and
/// need 5 recorded nights, like every baseline.
public enum ConsistencyEngine {
    public static let windowDays = [7, 14, 30]

    public static func consistency(history: [SleepSession], endingAt night: SleepNightKey? = nil) -> ConsistencyResult? {
        let mains = history.filter { $0.kind == .main }
        guard let end = night ?? mains.map(\.night).max() else { return nil }
        let windows = windowDays.compactMap { days -> ConsistencyWindow? in
            let first = end.adding(days: -(days - 1))
            let nights = mains.filter { $0.night >= first && $0.night <= end }
            let metrics = nights.map(SleepMetricsEngine.metrics(for:))
            guard let bedtime = BaselineEngine.baseline(metrics.map(\.bedtimeMinutes)),
                let wake = BaselineEngine.baseline(metrics.map(\.wakeMinutes)),
                let duration = BaselineEngine.baseline(metrics.map(\.asleepMinutes))
            else { return nil }
            return ConsistencyWindow(
                days: days, nights: bedtime.nights,
                bedtimeSD: bedtime.standardDeviation, wakeSD: wake.standardDeviation, durationSD: duration.standardDeviation,
                bedtimeMean: bedtime.value, wakeMean: wake.value, midpointMinutes: (bedtime.value + wake.value) / 2
            )
        }
        let last = mains.first { $0.night == end }.map { SleepMetricsEngine.metrics(for: $0).midpointMinutes }
        return ConsistencyResult(windows: windows, night: end, lastMidpointMinutes: last)
    }
}
