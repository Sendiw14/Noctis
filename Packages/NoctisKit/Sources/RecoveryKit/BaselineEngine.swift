import Foundation
import SleepKit

/// A personal baseline: the mean over the valid nights in the window,
/// and how much those nights vary.
public struct Baseline: Sendable, Equatable {
    public let value: Double
    /// Valid nights the mean is built from (5...14).
    public let nights: Int
    /// Sample standard deviation (n − 1) of those nights.
    public let standardDeviation: Double

    public init(value: Double, nights: Int, standardDeviation: Double = 0) {
        self.value = value
        self.nights = nights
        self.standardDeviation = standardDeviation
    }
}

/// The five baselines for one night. Each is nil until its metric has
/// `BaselineEngine.minimumNights` valid nights in the window.
public struct Baselines: Sendable, Equatable {
    public let sleepDuration: Baseline?
    public let bedtime: Baseline?
    public let wakeTime: Baseline?
    public let hrv: Baseline?
    public let restingHeartRate: Baseline?
    /// Nights in the window with an HRV value, even below the minimum.
    public let hrvNights: Int
    /// Nights in the window with a resting heart rate, even below the minimum.
    public let restingHeartRateNights: Int

    public init(
        sleepDuration: Baseline?,
        bedtime: Baseline?,
        wakeTime: Baseline?,
        hrv: Baseline?,
        restingHeartRate: Baseline?,
        hrvNights: Int? = nil,
        restingHeartRateNights: Int? = nil
    ) {
        self.sleepDuration = sleepDuration
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
        self.hrvNights = hrvNights ?? hrv?.nights ?? 0
        self.restingHeartRateNights = restingHeartRateNights ?? restingHeartRate?.nights ?? 0
    }

    public static let none = Baselines(sleepDuration: nil, bedtime: nil, wakeTime: nil, hrv: nil, restingHeartRate: nil)
}

/// Rolling 14-night baselines for sleep duration, bedtime, wake time, HRV
/// and resting heart rate. The window is the 14 calendar nights before the
/// night being judged — never the night itself. A baseline exists only
/// with 5 or more valid nights in that window; otherwise it's nil. It is
/// never invented, padded or carried over.
public enum BaselineEngine {
    public static let windowNights = 14
    public static let minimumNights = 5

    /// The nights in `history` that fall inside `night`'s window.
    public static func window(for night: SleepNightKey, in history: [NightMetrics]) -> [NightMetrics] {
        let first = night.adding(days: -windowNights)
        return history.filter { $0.night >= first && $0.night < night }
    }

    public static func baselines(for night: SleepNightKey, history: [NightMetrics]) -> Baselines {
        let nights = window(for: night, in: history)
        let hrv = nights.compactMap(\.hrv)
        let resting = nights.compactMap(\.restingHeartRate)
        return Baselines(
            sleepDuration: baseline(nights.map(\.asleepMinutes)),
            bedtime: baseline(nights.map(\.bedtimeMinutes)),
            wakeTime: baseline(nights.map(\.wakeMinutes)),
            hrv: baseline(hrv),
            restingHeartRate: baseline(resting),
            hrvNights: hrv.count,
            restingHeartRateNights: resting.count
        )
    }

    /// The mean and standard deviation of `values`, or nil below
    /// `minimumNights` values.
    public static func baseline(_ values: [Double]) -> Baseline? {
        guard values.count >= minimumNights else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        return Baseline(value: mean, nights: values.count, standardDeviation: variance.squareRoot())
    }
}
