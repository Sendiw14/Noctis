import Foundation
import HealthProviding
import SleepKit

/// The per-night values baselines and recovery are built from.
public struct NightMetrics: Sendable, Equatable {
    public let night: SleepNightKey
    public let wakeTime: Date
    public let asleepMinutes: Double
    /// Minutes after noon on the evening, local clock (11:00 PM = 660).
    public let bedtimeMinutes: Double
    /// Minutes after noon on the evening, local clock (7:00 AM = 1140).
    public let wakeMinutes: Double
    /// Mean SDNN (ms) of the night's HRV samples; nil without any.
    public let hrv: Double?
    /// Mean resting heart rate (bpm) for the wake-up; nil without any.
    public let restingHeartRate: Double?

    public init(
        night: SleepNightKey,
        wakeTime: Date,
        asleepMinutes: Double,
        bedtimeMinutes: Double,
        wakeMinutes: Double,
        hrv: Double?,
        restingHeartRate: Double?
    ) {
        self.night = night
        self.wakeTime = wakeTime
        self.asleepMinutes = asleepMinutes
        self.bedtimeMinutes = bedtimeMinutes
        self.wakeMinutes = wakeMinutes
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
    }
}

public enum NightMetricsBuilder {
    /// HRV samples count toward a night from bedtime until this long
    /// after waking.
    public static let hrvWindowAfterWake: TimeInterval = 30 * 60
    /// Resting heart rate samples count toward a night from bedtime until
    /// this long after waking (Apple Health dates the day's resting heart
    /// rate in the morning).
    public static let restingWindowAfterWake: TimeInterval = 4 * 3600

    /// One `NightMetrics` per main sleep, in the history's order.
    public static func metrics(for history: SleepHistory, hrv: [HRVSample], restingHeartRate: [HeartRateSample]) -> [NightMetrics] {
        history.nights.map { metrics(for: $0, hrv: hrv, restingHeartRate: restingHeartRate) }
    }

    public static func metrics(for session: SleepSession, hrv: [HRVSample], restingHeartRate: [HeartRateSample]) -> NightMetrics {
        let hrvValues =
            hrv
            .filter { $0.date >= session.bedtime && $0.date <= session.wakeTime.addingTimeInterval(hrvWindowAfterWake) }
            .map(\.sdnnMilliseconds)
        let restingValues =
            restingHeartRate
            .filter { $0.date >= session.bedtime && $0.date <= session.wakeTime.addingTimeInterval(restingWindowAfterWake) }
            .map(\.bpm)
        return NightMetrics(
            night: session.night,
            wakeTime: session.wakeTime,
            asleepMinutes: session.totals.asleep / 60,
            bedtimeMinutes: session.bedtimeMinutesAfterNoon,
            wakeMinutes: session.wakeMinutesAfterNoon,
            hrv: mean(hrvValues),
            restingHeartRate: mean(restingValues)
        )
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
