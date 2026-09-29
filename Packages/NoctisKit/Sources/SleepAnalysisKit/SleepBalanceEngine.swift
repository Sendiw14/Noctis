import Foundation
import RecoveryKit
import SleepKit

/// One point on the balance series: the balance over the 7 nights ending
/// on `night`; nil when too few of them have sleep recorded.
public struct SleepBalancePoint: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    /// Signed minutes: negative is behind your sleep need.
    public let minutes: Double?

    public init(night: SleepNightKey, minutes: Double?) {
        self.night = night
        self.minutes = minutes
    }
}

public struct SleepBalanceResult: Sendable, Equatable, Codable {
    /// The balance over the 7 nights ending on `night`: the sum of
    /// (asleep − need) for the nights with sleep recorded. Negative is
    /// behind, positive ahead. Nil when fewer than `minimumNights` of the
    /// 7 have sleep recorded.
    public let minutes: Double?
    /// The night the window ends on.
    public let night: SleepNightKey
    /// Nights in the window with sleep recorded (0...7).
    public let recordedNights: Int
    /// The last 14 nights' balances, oldest first.
    public let series: [SleepBalancePoint]

    public init(minutes: Double?, night: SleepNightKey, recordedNights: Int, series: [SleepBalancePoint]) {
        self.minutes = minutes
        self.night = night
        self.recordedNights = recordedNights
        self.series = series
    }
}

/// How your recent sleep adds up against your sleep need: a running
/// balance over 7 nights. It compares actual sleep with the need you set;
/// it is not a medical measure and says nothing about your health.
public enum SleepBalanceEngine {
    /// The nights the balance adds up.
    public static let windowNights = 7
    /// Nights with sleep recorded the window needs to give a balance.
    public static let minimumNights = BaselineEngine.minimumNights
    /// The series covers this many nights.
    public static let seriesNights = 14

    /// The balance ending on `night` (the newest night in `history` when
    /// nil), and the 14-night series ending there.
    public static func balance(history: [SleepSession], needMinutes: Double, endingAt night: SleepNightKey? = nil) -> SleepBalanceResult? {
        let mains = history.filter { $0.kind == .main }
        guard let end = night ?? mains.map(\.night).max() else { return nil }
        let asleepByNight = Dictionary(mains.map { ($0.night, $0.totals.asleep / 60) }, uniquingKeysWith: { first, _ in first })

        func window(endingAt last: SleepNightKey) -> (minutes: Double?, recorded: Int) {
            let values = (0..<windowNights).compactMap { asleepByNight[last.adding(days: -$0)] }
            guard values.count >= minimumNights, needMinutes > 0 else { return (nil, values.count) }
            return (values.reduce(0) { $0 + ($1 - needMinutes) }, values.count)
        }

        let series = (0..<seriesNights).reversed().map { offset -> SleepBalancePoint in
            let night = end.adding(days: -offset)
            return SleepBalancePoint(night: night, minutes: window(endingAt: night).minutes)
        }
        let current = window(endingAt: end)
        return SleepBalanceResult(minutes: current.minutes, night: end, recordedNights: current.recorded, series: series)
    }
}
