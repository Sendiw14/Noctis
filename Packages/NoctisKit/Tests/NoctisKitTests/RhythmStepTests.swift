import Testing

@testable import DesignSystem
@testable import NoctisCore
@testable import OnboardingFeature

// Onboarding step 2 (rhythm): the bedtime it shows is the same computation the app uses everywhere, the rulers keep their bounds, and a VoiceOver swipe moves
// them by a fixed step (15 minutes for the wake time, 30 for the sleep need) and never past either end.
struct RhythmStepTests {
    @Test func theBoundsAndGrainAreUnchanged() {
        #expect(RhythmBounds.wake == 180...720 && RhythmBounds.wakeStep == 5, "3:00 AM to 12:00 PM, every 5 minutes")
        #expect(RhythmBounds.need == 300...600 && RhythmBounds.needStep == 15, "5 h to 10 h, every 15 minutes")
    }

    @Test func theBedtimeIsTheSharedComputationAtEveryExtreme() {
        for wake in [RhythmBounds.wake.lowerBound, 420, RhythmBounds.wake.upperBound] {
            for need in [RhythmBounds.need.lowerBound, 480, RhythmBounds.need.upperBound] {
                let bedtime = noctisBedtimeMinutes(wakeMinutes: wake, needMinutes: need)
                #expect((0..<1440).contains(bedtime), Comment(rawValue: "wake \(wake) need \(need) -> \(bedtime)"))
                #expect((bedtime + need) % 1440 == wake % 1440, "going to bed that long before waking")
            }
        }
        #expect(noctisBedtimeMinutes(wakeMinutes: 420, needMinutes: 480) == 1380, "7:00 AM and 8 h is 11:00 PM")
    }

    @Test func aVoiceOverSwipeMovesTheWakeTimeByFifteenMinutes() {
        let range = RhythmBounds.wake
        #expect(NoctisRulerDial.accessibilitySnap(420 + 15, step: 15, range: range) == 435)
        #expect(NoctisRulerDial.accessibilitySnap(420 - 15, step: 15, range: range) == 405)
    }

    @Test func aVoiceOverSwipeMovesTheSleepNeedByThirtyMinutes() {
        let range = RhythmBounds.need
        #expect(NoctisRulerDial.accessibilitySnap(480 + 30, step: 30, range: range) == 510)
        #expect(NoctisRulerDial.accessibilitySnap(480 - 30, step: 30, range: range) == 450)
    }

    @Test func nothingMovesPastEitherEnd() {
        #expect(NoctisRulerDial.accessibilitySnap(10_000, step: 15, range: RhythmBounds.wake) == 720)
        #expect(NoctisRulerDial.accessibilitySnap(-10_000, step: 15, range: RhythmBounds.wake) == 180)
        #expect(NoctisRulerDial.accessibilitySnap(10_000, step: 30, range: RhythmBounds.need) == 600)
        #expect(NoctisRulerDial.accessibilitySnap(0, step: 30, range: RhythmBounds.need) == 300)
    }
}
