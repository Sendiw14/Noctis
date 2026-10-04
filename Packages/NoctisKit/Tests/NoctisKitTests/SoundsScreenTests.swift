import Foundation
import Testing

@testable import NightFeature
@testable import SoundKit

/// What the Sounds screen says and does (APP_RULES.md R31).
struct SoundsContentTests {
    @Test func sixSoundsInOrderEachInItsColor() {
        let tiles = SoundsBuilder.tiles(SoundPlayerState())
        #expect(tiles.map(\.title) == ["Brown noise", "Rain", "Ocean", "Wind", "Fireplace", "Ambient"])
        #expect(tiles.map(\.tone) == [.cocoa, .lavender, .sage, .butter, .orange, .apricot])
        #expect(tiles.map(\.symbol) == ["waveform", "cloud.rain", "water.waves", "wind", "flame", "sparkles"])
        #expect(tiles.allSatisfy { !$0.isCurrent && !$0.isPlaying && $0.stateText == nil })
        #expect(SoundKind.allCases.count == 6, "Forest and Night are not shipped: they need recordings")
    }

    @Test func thePlayingTileIsMarked() {
        let tiles = SoundsBuilder.tiles(SoundPlayerState(kind: .ocean, phase: .playing))
        let ocean = tiles[2]
        #expect(ocean.isCurrent && ocean.isPlaying && ocean.stateText == "Playing")
        #expect(ocean.accessibilityLabel == "Ocean, Playing" && ocean.accessibilityHint == "Pauses Ocean.")
        #expect(tiles.filter(\.isCurrent).count == 1)
        #expect(tiles[1].accessibilityLabel == "Rain" && tiles[1].accessibilityHint == "Plays Rain.")
    }

    @Test func aPausedOrInterruptedTileIsCurrentButNotPlaying() {
        let paused = SoundsBuilder.tiles(SoundPlayerState(kind: .rain, phase: .paused))[1]
        #expect(paused.isCurrent && !paused.isPlaying && paused.stateText == "Paused" && paused.accessibilityHint == "Plays Rain again.")
        let interrupted = SoundsBuilder.tiles(SoundPlayerState(kind: .rain, phase: .interrupted))[1]
        #expect(interrupted.isCurrent && !interrupted.isPlaying && interrupted.stateText == "Paused by iPhone")
    }

    @Test func nothingIsNowPlayingWhenNothingIsLoaded() {
        #expect(SoundsBuilder.nowPlaying(SoundPlayerState(), remaining: nil) == nil)
        #expect(SoundsBuilder.nowPlaying(SoundPlayerState(kind: .rain, phase: .stopped), remaining: nil) == nil)
    }

    @Test func nowPlayingCarriesTheSoundItsGainAndItsTimer() {
        let plan = SleepTimerPlan(start: Date(timeIntervalSince1970: 0), choice: .minutes30)
        let state = SoundPlayerState(kind: .fireplace, phase: .playing, gains: [.fireplace: 0.55], timer: plan)
        let content = SoundsBuilder.nowPlaying(state, remaining: 1781)
        #expect(content?.title == "Fireplace" && content?.isPlaying == true && content?.stateText == "Playing")
        #expect(content?.gain == 0.55 && content?.gainText == "55%")
        #expect(content?.timerText == "29:41" && content?.timerIsRunning == true)
        #expect(content?.timerLabel == "Sleep timer, 30 minutes left")
        #expect(content?.playPauseLabel == "Pause Fireplace")
    }

    @Test func withoutATimerTheButtonSaysTimer() {
        let content = SoundsBuilder.nowPlaying(SoundPlayerState(kind: .wind, phase: .paused), remaining: nil)
        #expect(content?.timerText == "Timer" && content?.timerIsRunning == false && content?.timerLabel == "Sleep timer, off")
        #expect(content?.playPauseLabel == "Play Wind" && content?.isPlaying == false && content?.gainText == "40%")
    }

    @Test func theRemainingTimeIsSpokenInTheLargestUnit() {
        #expect(SoundsBuilder.spokenRemaining(1781) == "30 minutes")
        #expect(SoundsBuilder.spokenRemaining(61) == "2 minutes")
        #expect(SoundsBuilder.spokenRemaining(60) == "1 minute")
        #expect(SoundsBuilder.spokenRemaining(45) == "45 seconds")
        #expect(SoundsBuilder.spokenRemaining(1) == "1 second")
    }

    @Test func theTimerSheetMarksTheChosenLength() {
        let none = SoundsBuilder.timerChoices(SoundPlayerState())
        #expect(none.map(\.choice) == [.off, .minutes15, .minutes30, .minutes45, .minutes60, .minutes90])
        #expect(none.filter(\.isSelected).map(\.choice) == [.off])
        let running = SoundPlayerState(kind: .rain, phase: .playing, timer: SleepTimerPlan(start: Date(), choice: .minutes45))
        #expect(SoundsBuilder.timerChoices(running).filter(\.isSelected).map(\.choice) == [.minutes45])
    }

    // MARK: The meter

    @Test func theMeterScaleRunsFromMinusFiftyToMinusTenDecibels() {
        #expect(SoundMeterScale.display(rms: 0) == 0)
        #expect(SoundMeterScale.display(rms: 0.0001) == 0)
        #expect(abs(SoundMeterScale.display(rms: powf(10, -50 / 20))) < 0.001)
        #expect(abs(SoundMeterScale.display(rms: powf(10, -30 / 20)) - 0.5) < 0.001)
        #expect(abs(SoundMeterScale.display(rms: powf(10, -10 / 20)) - 1) < 0.001)
        #expect(SoundMeterScale.display(rms: 1) == 1)
        var last: Float = -1
        for rms in stride(from: Float(0.001), through: 0.5, by: 0.01) {
            let value = SoundMeterScale.display(rms: rms)
            #expect(value >= last)
            last = value
        }
    }

    @Test func aQuietSoundStillMovesTheBars() {
        // Rain at its 40% default is about 0.047 RMS: well above the floor, well under the ceiling.
        let value = SoundMeterScale.display(rms: 0.047)
        #expect(value > 0.4 && value < 0.8)
    }

    @Test func theHistoryIsTheLast24ReadingsNewestLast() {
        var history = SoundMeterHistory()
        #expect(history.bars.count == 24 && history.bars.allSatisfy { $0 == 0 })
        for i in 1...30 { history.push(rms: Float(i) * 0.01) }
        #expect(history.bars.count == 24)
        #expect(history.latest == SoundMeterScale.display(rms: 0.30))
        #expect(history.bars.first == SoundMeterScale.display(rms: 0.07))
        history.reset()
        #expect(history.bars.allSatisfy { $0 == 0 })
    }

    // MARK: Copy

    @Test func theCopySaysWhatItIsAndMakesNoHealthClaims() {
        #expect(SoundsCopy.summary == "Made on your iPhone. Nothing downloads.")
        #expect(SoundsCopy.caption == "STEADY SOUNDS FOR WINDING DOWN")
        #expect(SoundsCopy.sleepWell == "Sleep well.")
        let banned = ["sleep better", "help", "cure", "treat", "heal", "anxiety", "insomnia", "stress", "deeper sleep", "faster", "proven", "clinical", "therap", "scientific", "improve"]
        var strings = [SoundsCopy.caption, SoundsCopy.summary, SoundsCopy.sleepWell, SoundsCopy.timerTitle, SoundsCopy.timerNote, SoundsCopy.interrupted, SoundsCopy.paused, SoundsCopy.playing]
        for phase in [SoundPlaybackPhase.playing, .paused, .interrupted] {
            let state = SoundPlayerState(kind: .rain, phase: phase, timer: SleepTimerPlan(start: Date(), choice: .minutes30))
            for tile in SoundsBuilder.tiles(state) { strings += [tile.title, tile.accessibilityLabel, tile.accessibilityHint, tile.stateText ?? ""] }
            if let playing = SoundsBuilder.nowPlaying(state, remaining: 100) {
                strings += [playing.title, playing.stateText, playing.gainText, playing.timerText, playing.playPauseLabel, playing.timerLabel]
            }
        }
        for text in strings {
            for word in banned {
                #expect(!text.lowercased().contains(word), Comment(rawValue: "\"\(text)\" contains \"\(word)\""))
            }
        }
    }
}

// MARK: - The view model

@MainActor
struct SoundsViewModelTests {
    final class Haptics { var count = 0 }

    static func make() -> (SoundsViewModel, PlayerBench, Haptics) {
        let bench = PlayerBench.make()
        let haptics = Haptics()
        let model = SoundsViewModel(player: bench.player, now: { bench.time.now }, haptic: { haptics.count += 1 }, sleeper: { await bench.time.sleep($0) })
        return (model, bench, haptics)
    }

    @Test func startsWithSixTilesAndNoCard() {
        let (model, _, _) = Self.make()
        #expect(model.tiles.count == 6 && model.nowPlaying == nil && !model.showsSleepWell)
        #expect(model.bars.count == 24 && model.bars.allSatisfy { $0 == 0 })
    }

    @Test func aTileTapPlaysThenPausesThenPlaysAgain() async {
        let (model, bench, _) = Self.make()
        model.tap(.rain)
        #expect(model.state.phase == .playing && model.nowPlaying?.title == "Rain")
        model.tap(.rain)
        #expect(model.state.phase == .paused)
        await bench.time.advance(0.4)
        model.tap(.rain)
        #expect(model.state.phase == .playing)
    }

    @Test func aTapOnAnotherTileCrossesToIt() {
        let (model, bench, _) = Self.make()
        model.tap(.rain)
        model.tap(.ocean)
        #expect(model.state.kind == .ocean && model.state.phase == .playing)
        #expect(bench.engine.last?.crossfadeSeconds == 1.5)
        #expect(model.tiles.filter(\.isPlaying).map(\.kind) == [.ocean])
    }

    @Test func aTapOnTheInterruptedTileResumesIt() {
        let (model, bench, _) = Self.make()
        model.tap(.wind)
        bench.session.emit(.interruptionBegan)
        #expect(model.state.phase == .interrupted && model.nowPlaying?.stateText == "Paused by iPhone")
        model.togglePlayPause()
        #expect(model.state.phase == .playing)
    }

    @Test func theSliderMovesTheCurrentSoundsGainOnly() {
        let (model, bench, _) = Self.make()
        model.setGain(0.9)
        #expect(bench.engine.commands.isEmpty, "nothing is loaded")
        model.tap(.fireplace)
        model.setGain(0.9)
        #expect(model.nowPlaying?.gain == 0.9 && model.nowPlaying?.gainText == "90%")
        #expect(model.state.gain(for: .rain) == 0.4)
    }

    @Test func choosingATimerStartsItAndClosesTheSheet() {
        let (model, _, _) = Self.make()
        model.tap(.rain)
        model.presentTimer()
        #expect(model.isTimerSheetPresented)
        model.selectTimer(.minutes30)
        #expect(!model.isTimerSheetPresented)
        #expect(model.state.timer?.duration == 1800)
        #expect(model.remaining == 1800)
        #expect(model.timerChoices.filter(\.isSelected).map(\.choice) == [.minutes30])
        model.selectTimer(.off)
        #expect(model.state.timer == nil && model.remaining == nil)
    }

    // MARK: The meter and the countdown run only while the screen is showing

    @Test func theMeterIsOnOnlyWhileVisibleAndPlaying() {
        let (model, bench, _) = Self.make()
        model.tap(.rain)
        #expect(!bench.engine.meterOn, "the screen isn't showing")
        model.appear()
        #expect(bench.engine.meterOn)
        model.disappear()
        #expect(!bench.engine.meterOn)
        model.appear()
        model.togglePlayPause()
        #expect(!bench.engine.meterOn, "paused")
    }

    @Test func aLevelBecomesABarAndOnlyWhileVisibleAndPlaying() async {
        let (model, bench, _) = Self.make()
        model.tap(.rain)
        bench.engine.meterHandler?(0.1)
        await bench.time.settle()
        #expect(model.level == 0, "not visible: nothing is shown")
        model.appear()
        bench.engine.meterHandler?(0.047)
        await bench.time.settle()
        #expect(model.level == SoundMeterScale.display(rms: 0.047))
        #expect(model.bars.last == SoundMeterScale.display(rms: 0.047) && model.bars.count == 24)
        model.togglePlayPause()
        #expect(model.bars.allSatisfy { $0 == 0 } && model.level == 0)
    }

    @Test func theCountdownTicksOnceASecondWhileVisible() async {
        let (model, bench, _) = Self.make()
        model.tap(.rain)
        model.selectTimer(.minutes15)
        model.appear()
        #expect(model.remaining == 900)
        await bench.time.advance(5)
        #expect(model.remaining == 895)
        await bench.time.advance(60)
        #expect(model.remaining == 835)
    }

    @Test func nothingTicksWhileTheScreenIsAway() async {
        let (model, bench, _) = Self.make()
        model.tap(.rain)
        model.selectTimer(.minutes15)
        model.appear()
        model.disappear()
        await bench.time.advance(1)
        // The player's own timer is waiting (it must stop the sound); the screen's ticker is not.
        #expect(bench.time.pending == 1)
    }

    @Test func whenTheTimerRunsOutItSaysSleepWellWithOneSoftHaptic() async {
        let (model, bench, haptics) = Self.make()
        model.tap(.rain)
        model.selectTimer(.minutes15)
        model.appear()
        await bench.time.advance(901)
        #expect(model.state.phase == .stopped && model.nowPlaying == nil)
        #expect(model.showsSleepWell)
        #expect(haptics.count == 1)
        #expect(model.remaining == nil)
        model.tap(.wind)
        #expect(!model.showsSleepWell)
    }

    @Test func comingBackAfterTheTimerEndedWhileAwayEndsIt() {
        let (model, bench, haptics) = Self.make()
        model.tap(.rain)
        model.selectTimer(.minutes15)
        bench.time.shift(by: 2000)
        model.appear()
        #expect(model.state.phase == .stopped && model.showsSleepWell && haptics.count == 1)
    }
}
