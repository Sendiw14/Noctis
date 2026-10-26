import Foundation
import Testing

@testable import NightFeature
@testable import NightKit
@testable import SoundKit

// The meditation's view model (APP_RULES.md R34): driven by the clock and the schedule's cues, with
// chimes and an optional voice that follow them and stop when the session does.

struct MeditationViewModelTests {
    final class Log {
        var announcements: [String] = []
        var completions = 0
    }

    /// The app was away: what the model sees as "now" jumps by this, and no sleeper sees it.
    final class Away: @unchecked Sendable {
        var seconds = 0.0
    }

    struct Bench {
        let model: MeditationViewModel
        let player: PlayerBench
        let audio: SilentMeditationAudio
        let log: Log
        let away: Away
        var time: ManualTime { player.time }
    }

    static func make(canSpeak: Bool = true, suite: String = UUID().uuidString, seed: ((UserDefaults) -> Void)? = nil) -> Bench {
        let player = PlayerBench.make()
        let audio = SilentMeditationAudio(canSpeak: canSpeak)
        let log = Log()
        let away = Away()
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        seed?(defaults)
        let time = player.time
        let model = MeditationViewModel(
            audio: audio, player: player.player, defaults: defaults, now: { time.now.addingTimeInterval(away.seconds) },
            sleeper: { await time.sleep($0) }, announce: { log.announcements.append($0) }, completion: { log.completions += 1 }
        )
        return Bench(model: model, player: player, audio: audio, log: log, away: away)
    }

    static func begin(_ bench: Bench, _ category: MeditationCategory, minutes: Int = 5, spoken: Bool = false) async {
        bench.model.choose(category: category)
        bench.model.choose(minutes: minutes)
        bench.model.setSpoken(spoken)
        bench.model.begin()
        await bench.time.settle()
    }

    static func keys(_ category: MeditationCategory) -> [String] { category.poolKeys }

    // MARK: Before beginning

    @Test func startsInSetupWithSleepTenMinutesAndTheExtrasOff() {
        let bench = Self.make()
        #expect(bench.model.state == .setup)
        #expect(bench.model.categoryID == .sleep && bench.model.minutes == 10)
        #expect(!bench.model.spokenOn && bench.model.canSpeak && bench.model.sound == nil)
        #expect(bench.model.remaining == 600 && bench.model.progress == 0 && bench.model.lineKey == nil)
        #expect(bench.model.offersSound)
    }

    @Test func theChoicesAreRememberedAndBadSavedOnesIgnored() async {
        let bench = Self.make()
        bench.model.choose(category: .bodyScan)
        bench.model.choose(minutes: 20)
        bench.model.choose(minutes: 7)
        #expect(bench.model.minutes == 20, "7 is not an option")
        bench.model.setSpoken(true)
        bench.model.choose(sound: .rain)
        bench.model.begin()
        await bench.time.settle()
        bench.model.end()

        let again = MeditationViewModel(audio: SilentMeditationAudio(), player: bench.player.player, defaults: bench.player.defaults)
        // That model had its own defaults; the one that ran has the keys.
        #expect(again.categoryID == .sleep)
        let bad = Self.make(seed: {
            $0.set("nonsense", forKey: MeditationViewModel.categoryKey)
            $0.set(3, forKey: MeditationViewModel.minutesKey)
        })
        #expect(bad.model.categoryID == .sleep && bad.model.minutes == 10)
        let good = Self.make(seed: {
            $0.set("bodyScan", forKey: MeditationViewModel.categoryKey)
            $0.set(20, forKey: MeditationViewModel.minutesKey)
            $0.set("rain", forKey: MeditationViewModel.soundKey)
        })
        #expect(good.model.categoryID == .bodyScan && good.model.minutes == 20 && good.model.sound == .rain && good.model.remaining == 1200)
    }

    @Test func spokenGuidanceCannotBeOnWhereThereIsNoVoice() {
        let bench = Self.make(canSpeak: false, seed: { $0.set(true, forKey: MeditationViewModel.spokenKey) })
        #expect(!bench.model.canSpeak && !bench.model.spokenOn)
        bench.model.setSpoken(true)
        #expect(!bench.model.spokenOn)
    }

    // MARK: The cues

    @Test func beginningSoundsTheStartChimeAndShowsNoLineYet() async {
        let bench = Self.make()
        await Self.begin(bench, .bodyScan)
        #expect(bench.model.state == .running)
        #expect(bench.audio.events == [.prepare, .chime(.start)])
        #expect(bench.model.lineKey == nil && bench.model.line == nil)
        #expect(bench.model.remaining == 300)
    }

    @Test func eachLineAppearsAtItsExactTimeEvenBetweenWholeSeconds() async {
        let bench = Self.make()
        await Self.begin(bench, .bodyScan)
        let keys = Self.keys(.bodyScan)

        await bench.time.advance(5.9)
        #expect(bench.model.lineKey == nil)
        await bench.time.advance(0.1)
        #expect(bench.model.lineKey == keys[0])
        #expect(bench.log.announcements == [MeditationCopy.string(keys[0])])

        await bench.time.advance(22.4)
        #expect(bench.model.lineKey == keys[0], "28.4 seconds in: the second line is not due")
        await bench.time.advance(0.1)
        #expect(bench.model.lineKey == keys[1], "28.5 seconds in")
        #expect(bench.model.line == MeditationCopy.string(keys[1]))
        #expect(bench.log.announcements.count == 2)
    }

    @Test func aWholeSessionSoundsItsChimesAndFinishesOnce() async {
        let bench = Self.make()
        await Self.begin(bench, .bodyScan)
        await bench.time.advance(299)
        #expect(bench.model.state == .running)
        await bench.time.advance(1)
        #expect(bench.model.state == .finished)
        #expect(bench.audio.chimes == [.start, .transition, .transition, .end])
        #expect(bench.log.completions == 1)
        #expect(bench.log.announcements.count == 13)
        #expect(bench.log.announcements.last == "Finished")
        #expect(bench.model.finishedCategory == .bodyScan && bench.model.finishedMinutes == 5)
        #expect(bench.model.progress == 1 && bench.model.remaining == 0)
        let events = bench.audio.events.count
        await bench.time.advance(1)
        #expect(bench.log.completions == 1 && bench.audio.events.count == events, "nothing more once it is over")
    }

    @Test func theSessionIsLetGoOfOnlyAfterTheClosingChimeHasRung() async {
        let bench = Self.make()
        await Self.begin(bench, .quietMind)
        await bench.time.advance(300)
        #expect(bench.model.state == .finished)
        #expect(!bench.audio.events.contains(.release))
        await bench.time.advance(MeditationChimeKind.end.seconds)
        #expect(!bench.audio.events.contains(.release))
        await bench.time.advance(1.5)
        #expect(bench.audio.events.contains(.release))
    }

    @Test func quietMindSaysNothingAndChimesAtTheThirds() async {
        let bench = Self.make()
        await Self.begin(bench, .quietMind, spoken: true)
        await bench.time.advance(100)
        #expect(bench.audio.chimes == [.start, .transition])
        await bench.time.advance(100)
        #expect(bench.audio.chimes == [.start, .transition, .transition])
        await bench.time.advance(100)
        #expect(bench.audio.chimes == [.start, .transition, .transition, .end])
        #expect(bench.model.lineKey == nil && bench.audio.spoken.isEmpty)
        #expect(bench.log.announcements == ["Finished"])
    }

    @Test func theLinesAreReadAloudOnlyWhenAskedAndAreTheCatalogsOwn() async {
        let quiet = Self.make()
        await Self.begin(quiet, .bodyScan)
        await quiet.time.advance(60)
        #expect(quiet.audio.spoken.isEmpty, "off by default")

        let bench = Self.make()
        await Self.begin(bench, .bodyScan, spoken: true)
        await bench.time.advance(30)
        let keys = Self.keys(.bodyScan)
        #expect(bench.audio.spoken == [MeditationCopy.string(keys[0]), MeditationCopy.string(keys[1])])
        bench.model.setSpoken(false)
        #expect(bench.audio.events.last == .silence, "off is silence at once")
        await bench.time.advance(30)
        #expect(bench.audio.spoken.count == 2)
    }

    // MARK: Pause, end, leave

    @Test func pausingStopsTheVoiceAndHoldsTheClockAndTheCues() async {
        let bench = Self.make()
        await Self.begin(bench, .bodyScan, spoken: true)
        await bench.time.advance(10)
        bench.model.pause()
        #expect(bench.model.state == .paused)
        #expect(bench.audio.events.last == .silence)
        let remaining = bench.model.remaining
        let events = bench.audio.events.count
        await bench.time.advance(120)
        #expect(bench.model.remaining == remaining && bench.audio.events.count == events, "no cue is sounded while paused")
        bench.model.resume()
        #expect(bench.model.state == .running)
        await bench.time.advance(18.5)
        #expect(bench.model.lineKey == Self.keys(.bodyScan)[1], "the clock picked up where it stopped")
    }

    @Test func endingEarlyIsQuietAndGoesBackToSetup() async {
        let bench = Self.make()
        await Self.begin(bench, .relax, spoken: true)
        await bench.time.advance(20)
        bench.model.end()
        #expect(bench.model.state == .setup && bench.model.lineKey == nil && bench.model.remaining == 300)
        #expect(bench.audio.events.suffix(2) == [.silence, .release])
        #expect(!bench.audio.chimes.contains(.end) && bench.log.completions == 0)
        let events = bench.audio.events.count
        await bench.time.advance(120)
        #expect(bench.audio.events.count == events, "nothing ticks once it is over")
    }

    @Test func leavingTheScreenEndsItAndLetsTheAudioGo() async {
        let bench = Self.make()
        await Self.begin(bench, .breathing)
        await bench.time.advance(10)
        bench.model.leave()
        #expect(bench.model.state == .setup)
        #expect(bench.audio.events.contains(.release))
        bench.model.leave()
        #expect(bench.model.state == .setup)
    }

    @Test func theChoicesAreLockedWhileItRuns() async {
        let bench = Self.make()
        await Self.begin(bench, .relax)
        bench.model.choose(category: .sleep)
        bench.model.choose(minutes: 20)
        bench.model.choose(sound: .ocean)
        #expect(bench.model.categoryID == .relax && bench.model.minutes == 5 && bench.model.sound == nil)
        bench.model.end()
    }

    @Test func againStartsOverWithTheSameChoices() async {
        let bench = Self.make()
        await Self.begin(bench, .sleep)
        await bench.time.advance(300)
        #expect(bench.model.state == .finished)
        bench.model.begin()
        await bench.time.settle()
        #expect(bench.model.state == .running && bench.model.categoryID == .sleep && bench.model.minutes == 5)
        #expect(bench.model.lineKey == nil && bench.model.remaining == 300 && bench.model.progress == 0)
        await bench.time.advance(6)
        #expect(bench.model.lineKey == Self.keys(.sleep)[0])
    }

    // MARK: Away and back

    @Test func comingBackShowsTheRightLineButDoesNotReplayWhatWasMissed() async {
        let bench = Self.make()
        await Self.begin(bench, .bodyScan, spoken: true)
        let before = bench.audio.events.count
        bench.away.seconds = 100
        bench.model.sceneBecameActive()
        // 100 s in: the fifth place (the line begun at 96 s), four seconds old.
        #expect(bench.model.lineKey == Self.keys(.bodyScan)[4])
        #expect(bench.audio.events.count == before, "nothing from the past is played late")
        #expect(bench.log.announcements.isEmpty)
        #expect(abs(bench.model.remaining - 200) < 1e-9)
    }

    @Test func aCueJustMissedIsStillSounded() async {
        let bench = Self.make()
        await Self.begin(bench, .bodyScan, spoken: true)
        bench.away.seconds = 98
        bench.model.sceneBecameActive()
        // The line at 96 s is two seconds old, and it opens the second part: its chime and its voice are not too late.
        #expect(bench.audio.chimes == [.start, .transition])
        #expect(bench.audio.spoken == [MeditationCopy.string(Self.keys(.bodyScan)[4])])
    }

    @Test func comingBackAfterItWouldHaveEndedFinishesIt() async {
        let bench = Self.make()
        await Self.begin(bench, .relax)
        bench.away.seconds = 1000
        bench.model.sceneBecameActive()
        #expect(bench.model.state == .finished && bench.log.completions == 1)
        #expect(bench.audio.chimes.last == .end)
    }

    // MARK: A sound underneath

    @Test func aSoundUnderneathPlaysQuietlyThenFadesAndLeavesTheVolumeAsItWas() async {
        let bench = Self.make()
        let player = bench.player.player
        let before = player.state.gain(for: .rain)
        bench.model.choose(sound: .rain)
        await Self.begin(bench, .sleep)
        #expect(player.state.kind == .rain && player.state.phase == .playing)
        #expect(player.state.gain(for: .rain) == MeditationViewModel.underlayGain)
        #expect(!bench.model.offersSound, "the row is not offered while a sound plays")

        await bench.time.advance(300)
        #expect(bench.model.state == .finished)
        await bench.time.advance(MeditationViewModel.underlayFadeSeconds + 1)
        #expect(player.state.phase == .stopped, "faded out and stopped")
        #expect(player.state.gain(for: .rain) == before, "and the person's own volume for rain is back")
    }

    @Test func endingEarlyAlsoFadesTheUnderlayAndRestoresTheVolume() async {
        let bench = Self.make()
        let player = bench.player.player
        let before = player.state.gain(for: .ocean)
        bench.model.choose(sound: .ocean)
        await Self.begin(bench, .relax)
        await bench.time.advance(10)
        bench.model.end()
        await bench.time.advance(MeditationViewModel.underlayFadeSeconds + 1)
        #expect(player.state.phase == .stopped)
        #expect(player.state.gain(for: .ocean) == before)
    }

    @Test func aSoundAlreadyPlayingIsLeftAloneFromStartToFinish() async {
        let bench = Self.make()
        let player = bench.player.player
        player.play(.wind)
        bench.model.choose(sound: .rain)
        await Self.begin(bench, .relax)
        #expect(player.state.kind == .wind && player.state.phase == .playing, "the wind-down's own sound is not replaced")
        await bench.time.advance(300)
        await bench.time.advance(10)
        #expect(player.state.kind == .wind && player.state.phase == .playing, "and it is not stopped")
    }

    @Test func noSoundChosenTouchesNoSound() async {
        let bench = Self.make()
        await Self.begin(bench, .relax)
        #expect(bench.player.player.state.phase == .stopped)
        await bench.time.advance(300)
        #expect(bench.player.player.state.phase == .stopped)
    }

    @Test func runningTheSameSoundTwiceInARowKeepsItQuietAndRestoresTheOriginalVolume() async {
        let bench = Self.make()
        let player = bench.player.player
        let before = player.state.gain(for: .rain)
        bench.model.choose(sound: .rain)
        await Self.begin(bench, .sleep)
        await bench.time.advance(300)
        bench.model.begin()
        await bench.time.settle()
        #expect(player.state.kind == .rain && player.state.phase == .playing, "the second session has its own sound")
        await bench.time.advance(MeditationViewModel.underlayFadeSeconds + 1)
        #expect(player.state.kind == .rain && player.state.phase == .playing, "and the first one's fade does not stop it")
        #expect(player.state.gain(for: .rain) == MeditationViewModel.underlayGain, "the first session's restore must not raise the second one's sound")
        bench.model.end()
        await bench.time.advance(MeditationViewModel.underlayFadeSeconds + 1)
        #expect(player.state.gain(for: .rain) == before)
    }
}
