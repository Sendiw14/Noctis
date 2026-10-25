import Testing

@testable import DesignSystem
@testable import OnboardingFeature

// Onboarding step 3 (sample night): the four durations on the tiles add up to the 8 h 25 m in the centre, and the words VoiceOver reads are as designed.
struct SampleNightStepTests {
    @Test func theDurationsAddUpToEightHoursTwentyFive() {
        let minutes = SampleNightFacts.stageMinutes.map(\.minutes)
        #expect(minutes == [92, 245, 128, 40], "Deep 1h 32m, Core 4h 5m, REM 2h 8m, Awake 40m")
        #expect(minutes.reduce(0, +) == SampleNightFacts.totalMinutes && SampleNightFacts.totalMinutes == 8 * 60 + 25)
    }

    @Test func theTilesAreInTheRingsOrder() {
        #expect(SampleNightFacts.stageMinutes.map(\.stage) == [.deep, .core, .rem, .awake])
    }

    @Test func theRingIsReadAsAOneSentenceSummary() {
        #expect(SampleNightFacts.accessibilitySummary == "Sample night: 8 hours 25 minutes asleep, sleep quality 87 percent")
        #expect(SampleNightFacts.spoken(92) == "1 hour 32 minutes")
        #expect(SampleNightFacts.spoken(40) == "40 minutes")
        #expect(SampleNightFacts.spoken(120) == "2 hours")
    }
}
