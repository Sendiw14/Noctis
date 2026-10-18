import Foundation
import NoctisText

/// Bedtime as minutes-since-midnight (0..<1440), computed as `wake - need`
/// and wrapped across midnight — pure and independently testable since
/// getting the modular arithmetic wrong here is exactly the kind of bug
/// that's invisible until someone picks a wake time before their sleep
/// need in raw minutes (e.g. a 12:30 AM wake with a 9h need).
public nonisolated func noctisBedtimeMinutes(wakeMinutes: Int, needMinutes: Int) -> Int {
    let raw = (wakeMinutes - needMinutes) % 1440
    return raw < 0 ? raw + 1440 : raw
}

/// Formats minutes-since-midnight as a locale-aware clock time (12h or 24h, whichever the user's locale prefers) — e.g. "11:00 PM" or "23:00". The one
/// clock formatter (`NoctisClockText`) with the device's calendar and locale: onboarding, Profile and every other surface print the same time the same way.
public nonisolated func noctisFormattedClock(minutesSinceMidnight: Int) -> String {
    NoctisClockText.string(minutesSinceMidnight: minutesSinceMidnight, calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent)
}

/// A duration in minutes as the app writes it everywhere: "8h", "9h 5m", "45m" (`NoctisDurationText`).
public nonisolated func noctisFormattedDuration(minutes: Int) -> String {
    NoctisDurationText.compact(minutes)
}

/// Rhythm's night strip: by default an 18-hour window, 6:00 PM through
/// 12:00 PM the next day, so its four labels (6P, 12A, 6A, 12P) land at
/// exactly 0, 1/3, 2/3 and 1 of its width.
public nonisolated let noctisNightStripStartMinutes = 18 * 60
public nonisolated let noctisNightStripSpanMinutes = 18 * 60
/// The window always ends at 12:00 PM the next day, counted in minutes
/// from the evening's own midnight.
public nonisolated let noctisNightStripEndMinutes = 36 * 60

/// The strip's window for a given bedtime: it starts at
/// `min(6 PM, bedtime rounded down to the hour − 1h)` and ends at 12 PM
/// the next day, so the moon is never pinned to the strip's edge — an
/// early 5:00 PM bedtime gets a 4 PM start and sits at its true position.
/// Bedtimes after midnight count as the next day.
public nonisolated func noctisNightStripWindow(bedtimeMinutes: Int) -> (startMinutes: Int, spanMinutes: Int) {
    let normalized = ((bedtimeMinutes % 1440) + 1440) % 1440
    let unfolded = normalized < 12 * 60 ? normalized + 1440 : normalized
    let start = min(noctisNightStripStartMinutes, (unfolded / 60) * 60 - 60)
    return (start, noctisNightStripEndMinutes - start)
}

/// Where `minutesSinceMidnight` falls on the night strip, as a fraction of
/// its width (0...1). Times earlier in the day than the strip's start fold
/// onto the next day, so a 7:00 AM wake sits after an 11:00 PM bedtime on
/// the same scale — the bedtime-to-wake distance is then exactly
/// `needMinutes / spanMinutes`. Times outside the window clamp to the
/// nearer end: the uncovered gap (12 PM to the start) is split at its
/// midpoint. With the bedtime-aware window from `noctisNightStripWindow`,
/// bedtime itself is always inside the window.
public nonisolated func noctisNightStripFraction(
    minutesSinceMidnight: Int,
    startMinutes: Int = noctisNightStripStartMinutes,
    spanMinutes: Int = noctisNightStripSpanMinutes
) -> Double {
    let normalized = ((minutesSinceMidnight % 1440) + 1440) % 1440
    let unfolded = normalized < startMinutes ? normalized + 1440 : normalized
    let offset = unfolded - startMinutes
    if offset > spanMinutes + (1440 - spanMinutes) / 2 { return 0 }
    let fraction = Double(offset) / Double(spanMinutes)
    return min(max(fraction, 0), 1)
}
