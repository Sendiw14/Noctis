import Foundation
import Testing

@testable import NightFeature
@testable import NightKit

// The breathing exercise's view model (APP_RULES.md R33): driven by the clock, a phase at a time,
// with haptics and announcements that follow the phases and stop when the exercise does.

nonisolated struct BreathingCopyTests {
    @Test func theSummaryIsThePhasesInOrder() {
        #expect(BreathingCopy.summary(.pattern(.calm)) == "Inhale 4 · Hold 2 · Exhale 6")
        #expect(BreathingCopy.summary(.pattern(.box)) == "Inhale 4 · Hold 4 · Exhale 4 · Hold 4")
        #expect(BreathingCopy.summary(.pattern(.relax)) == "Inhale 4 · Hold 7 · Exhale 8")
        #expect(BreathingCopy.spokenSummary(.pattern(.calm)) == "Inhale for 4, Hold for 2, Exhale for 6")
    }

    @Test func aPhaseIsAnnouncedByNameAndSeconds() {
        #expect(BreathingCopy.announcement(.inhale, seconds: 4) == "Inhale, 4 seconds")
        #expect(BreathingCopy.announcement(.hold, seconds: 1) == "Hold, 1 second")
        #expect(BreathingCopy.phaseName(.exhale) == "Exhale")
    }

    struct Left: Sendable {
        let seconds: Double
        let text: String
        let spoken: String
    }

    static let lefts: [Left] = [
        Left(seconds: 304, text: "5 min left", spoken: "5 minutes left"),
        Left(seconds: 302, text: "5 min left", spoken: "5 minutes left"),
        Left(seconds: 600, text: "10 min left", spoken: "10 minutes left"),
        Left(seconds: 128, text: "2 min left", spoken: "2 minutes left"),
        Left(seconds: 91, text: "2 min left", spoken: "2 minutes left"),
        Left(seconds: 90, text: "90 s left", spoken: "90 seconds left"),
        Left(seconds: 45.2, text: "46 s left", spoken: "46 seconds left"),
        Left(seconds: 1, text: "1 s left", spoken: "1 second left"),
        Left(seconds: 0, text: "0 s left", spoken: "0 seconds left"),
    ]

    @Test(arguments: lefts)
    func timeLeftIsToTheNearestMinuteThenInSeconds(left: Left) {
        #expect(BreathingCopy.remaining(left.seconds) == left.text)
        #expect(BreathingCopy.remainingSpoken(left.seconds) == left.spoken)
    }

    @Test func theCopyMakesNoClaimsAboutTheBodyOrMind() {
        let words = [BreathingCopy.line, BreathingCopy.hapticsNote, BreathingCopy.finishedTitle, BreathingCopy.finishedLine(pattern: .pattern(.calm), minutes: 5)]
            .joined(separator: " ").lowercased()
        #expect(BreathingCopy.line == "A slow breathing exercise.")
        for banned in ["anxiety", "stress", "treat", "cure", "heal", "therapy", "medical", "clinical", "better sleep", "fall asleep", "score", "streak"] {
            #expect(!words.contains(banned), Comment(rawValue: "the breathing copy says \"\(banned)\""))
        }
    }
}

struct BreathingViewModelTests {
    final class Log {
        var announcements: [String] = []
        var completions = 0
    }

    /// Moves what the model sees as "now" by a jump the sleepers don't see: the app was away.
    final class Away: @unchecked Sendable {
        var seconds = 0.0
    }

    struct Bench {
        let model: BreathingViewModel
        let time: ManualTime
        let haptics: SilentBreathingHaptics
        let log: Log
        let away: Away
        let defaults: UserDefaults
    }

    static func make(haptics available: Bool = true, suite: String = UUID().uuidString, seed: ((UserDefaults) -> Void)? = nil) -> Bench {
        let time = ManualTime()
        let silent = SilentBreathingHaptics(available: available)
        let log = Log()
        let away = Away()
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        seed?(defaults)
        let model = BreathingViewModel(
            haptics: silent, defaults: defaults, now: { time.now.addingTimeInterval(away.seconds) }, sleeper: { await time.sleep($0) },
            announce: { log.announcements.append($0) }, completion: { log.completions += 1 }
        )
        return Bench(model: model, time: time, haptics: silent, log: log, away: away, defaults: defaults)
    }

    // MARK: Before beginning

    @Test func startsInSetupWithCalmFiveMinutesAndHapticsOff() {
        let bench = Self.make()
        #expect(bench.model.state == .setup)
        #expect(bench.model.patternID == .calm && bench.model.minutes == 5)
        #expect(bench.model.hapticsAvailable && !bench.model.hapticsOn)
        #expect(bench.model.remaining == 300)
        #expect(bench.model.moment == nil)
    }

    @Test func theChoicesAreRememberedAndBadSavedOnesAreIgnored() async {
        let bench = Self.make()
        bench.model.choose(pattern: .box)
        bench.model.choose(minutes: 10)
        bench.model.choose(minutes: 7)
        #expect(bench.model.minutes == 10, "7 is not an option")
        #expect(bench.model.remaining == 608, "ten minutes of box breathing is 38 whole breaths")
        bench.model.setHaptics(true)
        bench.model.begin()
        await bench.time.settle()
        bench.model.end()

        let defaults = bench.defaults
        let again = BreathingViewModel(haptics: SilentBreathingHaptics(available: true), defaults: defaults)
        #expect(again.patternID == .box && again.minutes == 10 && again.hapticsOn)

        let bad = Self.make(seed: { $0.set("nonsense", forKey: BreathingViewModel.patternKey); $0.set(3, forKey: BreathingViewModel.minutesKey) })
        #expect(bad.model.patternID == .calm && bad.model.minutes == 5)
    }

    @Test func hapticsCannotBeOnWhereTheDeviceHasNone() {
        let bench = Self.make(haptics: false, seed: { $0.set(true, forKey: BreathingViewModel.hapticsKey) })
        #expect(!bench.model.hapticsAvailable && !bench.model.hapticsOn)
        bench.model.setHaptics(true)
        #expect(!bench.model.hapticsOn)
        bench.model.begin()
        #expect(bench.haptics.played.isEmpty)
    }

    // MARK: Phases

    @Test func beginningStartsTheInhaleAndAnnouncesIt() async {
        let bench = Self.make()
        bench.model.setHaptics(true)
        bench.model.begin()
        await bench.time.settle()
        #expect(bench.model.state == .running)
        #expect(bench.model.moment?.kind == .inhale && bench.model.countdown == 4 && bench.model.phaseName == "Inhale")
        #expect(bench.log.announcements == ["Inhale, 4 seconds"])
        let ring = bench.model.ring
        #expect(ring.target == 1 && ring.duration == 4 && ring.level == 0 && !ring.jumped, "a new breath flows on from the last, it does not jump")
        #expect(bench.haptics.played.map(\.style) == [.swell])
        #expect(bench.haptics.played.first?.duration == 4)
    }

    @Test func eachPhaseChangesAtItsExactSecondWithItsOwnRingAndHaptic() async {
        let bench = Self.make()
        bench.model.setHaptics(true)
        bench.model.begin()
        await bench.time.settle()

        await bench.time.advance(3.9)
        #expect(bench.model.moment?.kind == .inhale && bench.model.countdown == 1)
        #expect(bench.log.announcements.count == 1, "no announcement within a phase")

        await bench.time.advance(0.1)
        #expect(bench.model.moment?.kind == .hold && bench.model.countdown == 2)
        #expect(bench.model.ring.target == 1 && bench.model.ring.duration == 2 && !bench.model.ring.jumped)
        #expect(bench.log.announcements.last == "Hold, 2 seconds")

        await bench.time.advance(2)
        #expect(bench.model.moment?.kind == .exhale && bench.model.countdown == 6)
        #expect(bench.model.ring.target == 0 && bench.model.ring.duration == 6)
        #expect(bench.log.announcements.last == "Exhale, 6 seconds")

        await bench.time.advance(6)
        #expect(bench.model.moment?.kind == .inhale && bench.model.moment?.cycle == 1)
        #expect(bench.haptics.played.map(\.style) == [.swell, .tick, .fade, .swell])
        #expect(bench.log.announcements == ["Inhale, 4 seconds", "Hold, 2 seconds", "Exhale, 6 seconds", "Inhale, 4 seconds"])
    }

    @Test func theLevelBarStepsOnceASecond() async {
        let bench = Self.make()
        bench.model.begin()
        await bench.time.settle()
        #expect(bench.model.level == 0)
        await bench.time.advance(1)
        #expect(abs(bench.model.level - BreathingSchedule.ease(0.25)) < 1e-9)
        await bench.time.advance(1)
        #expect(abs(bench.model.level - 0.5) < 1e-9)
        await bench.time.advance(2)
        #expect(bench.model.level == 1)
    }

    @Test func theRemainingTimeCountsDown() async {
        let bench = Self.make()
        bench.model.choose(minutes: 2)
        bench.model.begin()
        await bench.time.settle()
        #expect(bench.model.remaining == 120)
        await bench.time.advance(30)
        #expect(bench.model.remaining == 90)
    }

    // MARK: Pause, end, finish

    @Test func pausingFreezesTheCircleStopsTheHapticsAndHoldsTheClock() async {
        let bench = Self.make()
        bench.model.setHaptics(true)
        bench.model.begin()
        await bench.time.settle()
        await bench.time.advance(2)
        let stopsBefore = bench.haptics.stops
        bench.model.pause()
        #expect(bench.model.state == .paused)
        #expect(bench.haptics.stops == stopsBefore + 1)
        let frozen = bench.model.ring
        #expect(frozen.duration == 0 && frozen.target == frozen.level && frozen.jumped)
        #expect(abs(frozen.level - 0.5) < 1e-9)

        let remaining = bench.model.remaining
        await bench.time.advance(60)
        #expect(bench.model.moment?.kind == .inhale && bench.model.countdown == 2, "time paused does not count")
        #expect(bench.model.remaining == remaining)
        #expect(bench.haptics.played.count == 1)

        bench.model.resume()
        #expect(bench.model.state == .running)
        #expect(bench.model.ring.jumped && bench.model.ring.target == 1 && abs(bench.model.ring.duration - 2) < 1e-9)
        #expect(bench.haptics.played.count == 2, "the rest of the swell")
        #expect(abs((bench.haptics.played.last?.duration ?? 0) - 2) < 1e-9)
        await bench.time.advance(2)
        #expect(bench.model.moment?.kind == .hold)
    }

    @Test func endingEarlyGoesBackToSetupQuietly() async {
        let bench = Self.make()
        bench.model.setHaptics(true)
        bench.model.begin()
        await bench.time.settle()
        await bench.time.advance(5)
        bench.model.end()
        #expect(bench.model.state == .setup && bench.model.moment == nil)
        #expect(bench.log.completions == 0)
        #expect(!bench.log.announcements.contains("Finished"))
        #expect(bench.haptics.stops >= 1)
        #expect(bench.model.ring.level == 0 && bench.model.ring.jumped)
        await bench.time.advance(30)
        #expect(bench.model.moment == nil, "nothing ticks once it is over")
        #expect(bench.model.remaining == 300)
    }

    @Test func runningTheWholeTimeFinishesOnceWithASoftHaptic() async {
        let bench = Self.make()
        bench.model.choose(minutes: 2)
        bench.model.setHaptics(true)
        bench.model.begin()
        await bench.time.settle()
        await bench.time.advance(119)
        #expect(bench.model.state == .running)
        await bench.time.advance(1)
        #expect(bench.model.state == .finished)
        #expect(bench.log.completions == 1)
        #expect(bench.log.announcements.last == "Finished")
        #expect(bench.model.finishedPattern?.id == .calm && bench.model.finishedMinutes == 2)
        #expect(bench.model.remaining == 0 && bench.model.level == 0)
        let stops = bench.haptics.stops
        await bench.time.advance(30)
        #expect(bench.log.completions == 1 && bench.haptics.stops == stops)
    }

    @Test func againStartsOverWithTheSameChoices() async {
        let bench = Self.make()
        bench.model.choose(pattern: .relax)
        bench.model.choose(minutes: 2)
        bench.model.begin()
        await bench.time.settle()
        await bench.time.advance(140)
        #expect(bench.model.state == .finished)
        bench.model.begin()
        await bench.time.settle()
        #expect(bench.model.state == .running && bench.model.patternID == .relax && bench.model.minutes == 2)
        #expect(bench.model.moment?.kind == .inhale && bench.model.moment?.cycle == 0)
        #expect(bench.model.remaining == 133)
    }

    @Test func theChoicesAreLockedWhileItRuns() async {
        let bench = Self.make()
        bench.model.begin()
        await bench.time.settle()
        bench.model.choose(pattern: .box)
        bench.model.choose(minutes: 10)
        #expect(bench.model.patternID == .calm && bench.model.minutes == 5)
        bench.model.end()
    }

    @Test func leavingTheScreenEndsItAndLeavesNothingRunning() async {
        let bench = Self.make()
        bench.model.setHaptics(true)
        bench.model.begin()
        await bench.time.settle()
        await bench.time.advance(3)
        bench.model.leave()
        #expect(bench.model.state == .setup)
        let stops = bench.haptics.stops
        #expect(stops >= 1)
        await bench.time.advance(60)
        #expect(bench.haptics.played.count == 1 && bench.log.announcements.count == 1)

        bench.model.leave()
        #expect(bench.haptics.stops == stops, "leaving from setup does nothing")
    }

    // MARK: Away and back

    @Test func comingBackReadsTheClockAndStartsTheCircleFromWhereItReallyIs() async {
        let bench = Self.make()
        bench.model.setHaptics(true)
        bench.model.begin()
        await bench.time.settle()
        // The phone was locked for 37 seconds: three whole breaths and one second of the fourth.
        bench.away.seconds = 37
        bench.model.sceneBecameActive()
        let moment = bench.model.moment
        #expect(moment?.cycle == 3 && moment?.kind == .inhale && bench.model.countdown == 3)
        let ring = bench.model.ring
        #expect(ring.jumped && ring.target == 1 && abs(ring.duration - 3) < 1e-9)
        #expect(abs(ring.level - BreathingSchedule.ease(0.25)) < 1e-9)
        let plan = bench.haptics.played.last
        #expect(plan?.style == .swell && abs((plan?.duration ?? 0) - 3) < 1e-9)
        #expect(bench.model.remaining == 263)
    }

    @Test func comingBackAfterItWouldHaveEndedFinishesIt() async {
        let bench = Self.make()
        bench.model.choose(minutes: 2)
        bench.model.begin()
        await bench.time.settle()
        bench.away.seconds = 500
        bench.model.sceneBecameActive()
        #expect(bench.model.state == .finished)
        #expect(bench.log.completions == 1)
    }

    @Test func turningHapticsOnMidPhasePlaysTheRestAndOffIsSilenceAtOnce() async {
        let bench = Self.make()
        bench.model.begin()
        await bench.time.settle()
        await bench.time.advance(1)
        #expect(bench.haptics.played.isEmpty)
        bench.model.setHaptics(true)
        #expect(bench.haptics.played.count == 1 && abs((bench.haptics.played[0].duration) - 3) < 1e-9)
        let stops = bench.haptics.stops
        bench.model.setHaptics(false)
        #expect(bench.haptics.stops == stops + 1)
        await bench.time.advance(3)
        #expect(bench.haptics.played.count == 1, "off stays off through the next phase")
    }
}
