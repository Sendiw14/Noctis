import Foundation

/// Clock arithmetic on minutes since midnight. A bedtime window crosses midnight (11:00 PM
/// to 7:00 AM), so every value is wrapped into 0..<1440 and every difference is taken on
/// the circle: no `Date`, no calendar, nothing that a DST change could shift.
public enum BedtimeClock {
    public static let minutesPerDay = 1440

    /// `minutes` as a clock time: 0..<1440.
    public static func wrap(_ minutes: Int) -> Int {
        ((minutes % minutesPerDay) + minutesPerDay) % minutesPerDay
    }

    /// Minutes from `from` forward to `to` on the clock: 0..<1440. 11:00 PM to 7:00 AM is 480.
    public static func forward(from: Int, to: Int) -> Int {
        wrap(to - from)
    }

    /// The shortest signed distance from `reference` to `time` on the clock, in
    /// -720..<720: positive when `time` is later. 11:50 PM to 12:20 AM is +30.
    public static func signedDistance(from reference: Int, to time: Int) -> Int {
        wrap(time - reference + minutesPerDay / 2) - minutesPerDay / 2
    }

    /// `minutes` rounded to the nearest multiple of `step` (halves away from zero).
    public static func rounded(_ minutes: Double, to step: Int) -> Int {
        Int((minutes / Double(step)).rounded()) * step
    }
}
