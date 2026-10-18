import Testing
@testable import DesignSystem
@testable import NoctisCore

struct SleepRhythmMathTests {
    @Test func wakeAfterMidnightWithNineHourNeedWrapsToAfternoonBedtime() {
        // Wake 12:30 AM (30 min), need 9h (540 min) -> bedtime 3:30 PM (930 min).
        #expect(noctisBedtimeMinutes(wakeMinutes: 30, needMinutes: 9 * 60) == 930)
    }

    @Test func wakeSevenAMWithEightHourNeedGivesElevenPMBedtime() {
        // Wake 7:00 AM (420 min), need 8h (480 min) -> bedtime 11:00 PM (1380 min).
        #expect(noctisBedtimeMinutes(wakeMinutes: 420, needMinutes: 8 * 60) == 1380)
    }

    @Test func wakeThreeAMWithTenHourNeedGivesFivePMBedtimePreviousEvening() {
        // Wake 3:00 AM (180 min), need 10h (600 min) -> bedtime 5:00 PM (1020 min).
        #expect(noctisBedtimeMinutes(wakeMinutes: 180, needMinutes: 10 * 60) == 1020)
    }

    @Test func bedtimeIsAlwaysWithinAFullDay() {
        for wake in stride(from: 0, to: 1440, by: 37) {
            for need in stride(from: 60, to: 900, by: 53) {
                let bedtime = noctisBedtimeMinutes(wakeMinutes: wake, needMinutes: need)
                #expect(bedtime >= 0 && bedtime < 1440)
            }
        }
    }

    /// Onboarding used to pad ("8h 00m", "9h 05m") while every other surface wrote "8h" and "9h 5m": one fact, two spellings. It is the app's one duration now
    /// (QA part 4, QA-118); the padded spellings are gone with their function body.
    @Test func formattedDurationIsTheAppsOneDuration() {
        #expect(noctisFormattedDuration(minutes: 8 * 60) == "8h")
        #expect(noctisFormattedDuration(minutes: 9 * 60 + 5) == "9h 5m")
        #expect(noctisFormattedDuration(minutes: 45) == "45m")
        #expect(noctisFormattedDuration(minutes: 7 * 60 + 30) == NoctisFormat.compactDuration(7 * 60 + 30))
    }
}

struct NightStripMathTests {
    @Test func elevenPMToSevenAMCoversEightEighteenthsOfAnEighteenHourStrip() {
        let width = 360.0
        let bedX = width * noctisNightStripFraction(minutesSinceMidnight: 23 * 60)
        let wakeX = width * noctisNightStripFraction(minutesSinceMidnight: 7 * 60)
        #expect(noctisNightStripSpanMinutes == 18 * 60)
        #expect(abs((wakeX - bedX) - width * 8 / 18) < 0.0001)
        #expect(abs(bedX - width * 5 / 18) < 0.0001)
        #expect(abs(wakeX - width * 13 / 18) < 0.0001)
    }

    @Test func labelsSitAtExactThirdsOfTheStrip() {
        #expect(noctisNightStripFraction(minutesSinceMidnight: 18 * 60) == 0)
        #expect(abs(noctisNightStripFraction(minutesSinceMidnight: 0) - 1.0 / 3) < 0.0001)
        #expect(abs(noctisNightStripFraction(minutesSinceMidnight: 6 * 60) - 2.0 / 3) < 0.0001)
        #expect(noctisNightStripFraction(minutesSinceMidnight: 12 * 60) == 1)
    }

    @Test func barWidthAlwaysEqualsSleepNeedWhenBothEndsAreInTheWindow() {
        for wake in stride(from: 5 * 60, through: 12 * 60, by: 5) {
            for need in stride(from: 5 * 60, through: 10 * 60, by: 15) {
                let bedtime = noctisBedtimeMinutes(wakeMinutes: wake, needMinutes: need)
                let bedFraction = noctisNightStripFraction(minutesSinceMidnight: bedtime)
                let wakeFraction = noctisNightStripFraction(minutesSinceMidnight: wake)
                guard bedFraction > 0 else { continue } // bedtime before 6 PM clamps
                #expect(abs((wakeFraction - bedFraction) - Double(need) / Double(18 * 60)) < 0.0001)
            }
        }
    }

    @Test func timesOutsideTheWindowClamp() {
        // 5 PM is an early bedtime (pins to the start), 1 PM a late wake
        // (pins to the end) — not both folded onto the next day.
        #expect(noctisNightStripFraction(minutesSinceMidnight: 17 * 60) == 0)
        #expect(noctisNightStripFraction(minutesSinceMidnight: 13 * 60) == 1)
    }

    @Test func earlyBedtimeGetsItsTruePositionInsteadOfPinningToTheEdge() {
        // Wake 3:00 AM with a 10h need: bedtime 5:00 PM, before the default
        // 6 PM start. The window moves to 4 PM (5 PM − 1h) through 12 PM.
        let bedtime = noctisBedtimeMinutes(wakeMinutes: 3 * 60, needMinutes: 10 * 60)
        #expect(bedtime == 17 * 60)
        let window = noctisNightStripWindow(bedtimeMinutes: bedtime)
        #expect(window.startMinutes == 16 * 60)
        #expect(window.spanMinutes == 20 * 60)

        let width = 400.0
        let bedX = width * noctisNightStripFraction(minutesSinceMidnight: bedtime, startMinutes: window.startMinutes, spanMinutes: window.spanMinutes)
        let wakeX = width * noctisNightStripFraction(minutesSinceMidnight: 3 * 60, startMinutes: window.startMinutes, spanMinutes: window.spanMinutes)
        #expect(abs(bedX - width / 20) < 0.0001) // 1h into a 20h strip, not 0
        #expect(abs((wakeX - bedX) - width * 10 / 20) < 0.0001) // bar is exactly the 10h need

        // The labels re-space on the new scale.
        let sixPM = noctisNightStripFraction(minutesSinceMidnight: 18 * 60, startMinutes: window.startMinutes, spanMinutes: window.spanMinutes)
        let midnight = noctisNightStripFraction(minutesSinceMidnight: 0, startMinutes: window.startMinutes, spanMinutes: window.spanMinutes)
        #expect(abs(sixPM - 2.0 / 20) < 0.0001)
        #expect(abs(midnight - 8.0 / 20) < 0.0001)
    }

    @Test func windowStartsAnHourBeforeAnyBedtimeBefore7PMAndAt6PMOtherwise() {
        #expect(noctisNightStripWindow(bedtimeMinutes: 18 * 60 + 30).startMinutes == 17 * 60)
        #expect(noctisNightStripWindow(bedtimeMinutes: 19 * 60).startMinutes == 18 * 60)
        #expect(noctisNightStripWindow(bedtimeMinutes: 23 * 60).startMinutes == 18 * 60)
        #expect(noctisNightStripWindow(bedtimeMinutes: 1 * 60).startMinutes == 18 * 60) // after midnight
        #expect(noctisNightStripWindow(bedtimeMinutes: 23 * 60).spanMinutes == 18 * 60)
    }
}
