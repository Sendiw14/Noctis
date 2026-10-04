import Foundation
import Testing

@testable import NightFeature
@testable import NightKit
@testable import NoctisCore
@testable import SoundKit

// The wind-down session's engine (APP_RULES.md R32): the clock, the state machine, the numbers the
// scene is drawn from, and the view model that runs a session.

nonisolated struct WindDownMachineTests {
    static let table: [(WindDownState, WindDownEvent, WindDownState)] = [
        (.idle, .begin, .running),
        (.running, .pause, .paused),
        (.paused, .resume, .running),
        (.running, .reachedEnd, .ending),
        (.paused, .reachedEnd, .ending),
        (.running, .endEarly, .ending),
        (.paused, .endEarly, .ending),
        (.ending, .endingDone, .finished),
        (.finished, .reset, .idle),
        (.ending, .reset, .idle),
        (.running, .reset, .idle),
        (.paused, .reset, .idle),
    ]

    @Test(arguments: table.indices)
    func everyTransitionThatExists(index: Int) {
        let (from, event, to) = Self.table[index]
        #expect(WindDownMachine.reduce(from, event) == to, Comment(rawValue: "\(from) + \(event)"))
    }

    @Test func everyOtherPairChangesNothing() {
        for state in WindDownState.allCases {
            for event in WindDownEvent.allCases where !Self.table.contains(where: { $0.0 == state && $0.1 == event }) {
                #expect(WindDownMachine.reduce(state, event) == state, Comment(rawValue: "\(state) + \(event)"))
            }
        }
    }
}

nonisolated struct WindDownClockTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theOptionsAreTenTwentyAndThirtyMinutesAndTwentyIsTheDefault() {
        #expect(WindDownClock.options == [10, 20, 30])
        #expect(WindDownClock.defaultMinutes == 20)
        for minutes in WindDownClock.options { #expect(WindDownClock(minutes: minutes).plannedSeconds == Double(minutes * 60)) }
    }

    @Test func progressIsTheShareOfThePlannedTimeThatHasPassed() {
        var clock = WindDownClock(minutes: 20)
        #expect(clock.progress(at: start) == 0, "not started")
        clock.start(at: start)
        #expect(clock.progress(at: start) == 0)
        #expect(clock.progress(at: start.addingTimeInterval(360)) == 0.3)
        #expect(clock.progress(at: start.addingTimeInterval(720)) == 0.6)
        #expect(clock.progress(at: start.addingTimeInterval(1080)) == 0.9)
        #expect(clock.progress(at: start.addingTimeInterval(1200)) == 1)
        #expect(clock.progress(at: start.addingTimeInterval(9999)) == 1)
        #expect(clock.progress(at: start.addingTimeInterval(-50)) == 0)
    }

    @Test(arguments: [10, 20, 30])
    func eachLengthReachesTheEndAtItsOwnTime(minutes: Int) {
        var clock = WindDownClock(minutes: minutes)
        clock.start(at: start)
        let end = start.addingTimeInterval(Double(minutes * 60))
        #expect(!clock.isComplete(at: end.addingTimeInterval(-1)))
        #expect(clock.isComplete(at: end))
        #expect(clock.remaining(at: start) == Double(minutes * 60))
        #expect(clock.remaining(at: end) == 0)
        #expect(clock.remaining(at: start.addingTimeInterval(Double(minutes * 30))) == Double(minutes * 30))
    }

    @Test func pausedTimeDoesNotCount() {
        var clock = WindDownClock(minutes: 10)
        clock.start(at: start)
        clock.pause(at: start.addingTimeInterval(120))
        // A long pause: the clock stands still.
        #expect(clock.elapsed(at: start.addingTimeInterval(120)) == 120)
        #expect(clock.elapsed(at: start.addingTimeInterval(5000)) == 120)
        clock.resume(at: start.addingTimeInterval(620))
        #expect(clock.elapsed(at: start.addingTimeInterval(620)) == 120)
        #expect(clock.elapsed(at: start.addingTimeInterval(680)) == 180)
        #expect(clock.progress(at: start.addingTimeInterval(920)) == 0.7)
    }

    @Test func aSecondPauseAddsToTheFirst() {
        var clock = WindDownClock(minutes: 30)
        clock.start(at: start)
        clock.pause(at: start.addingTimeInterval(60))
        clock.resume(at: start.addingTimeInterval(160))
        clock.pause(at: start.addingTimeInterval(460))
        clock.resume(at: start.addingTimeInterval(560))
        // 600 s on the clock, less 100 s and 100 s paused: 400 s of session.
        #expect(clock.elapsed(at: start.addingTimeInterval(600)) == 400)
    }

    @Test func catchingUpAfterBeingAwayIsJustReadingTheClock() {
        // Locked for 14 minutes with nothing ticking: the next read is exactly 14 minutes in.
        var clock = WindDownClock(minutes: 20)
        clock.start(at: start)
        #expect(abs(clock.progress(at: start.addingTimeInterval(840)) - 0.7) < 1e-9)
        #expect(!clock.isComplete(at: start.addingTimeInterval(840)))
        // Away for an hour: it has ended, and says so.
        #expect(clock.isComplete(at: start.addingTimeInterval(3600)))
    }

    @Test func pausingBeforeStartingOrResumingWithoutPausingDoesNothing() {
        var clock = WindDownClock(minutes: 10)
        clock.pause(at: start)
        clock.resume(at: start)
        #expect(clock.startedAt == nil && clock.pausedAt == nil && clock.pausedTotal == 0)
        clock.start(at: start)
        clock.resume(at: start.addingTimeInterval(30))
        #expect(clock.pausedTotal == 0)
    }
}

nonisolated struct WindDownVisualsTests {
    @Test func theProductGetsQuieterInThreeStages() {
        #expect(WindDownStage.stage(for: 0) == .full)
        #expect(WindDownStage.stage(for: 0.299) == .full)
        #expect(WindDownStage.stage(for: 0.3) == .reduced)
        #expect(WindDownStage.stage(for: 0.599) == .reduced)
        #expect(WindDownStage.stage(for: 0.6) == .minimal)
        #expect(WindDownStage.stage(for: 1) == .minimal)
    }

    @Test func transitionsLengthenAsTheSessionGoesOn() {
        #expect(WindDownStage.transitionSeconds(for: 0) == 0.35)
        #expect(abs(WindDownStage.transitionSeconds(for: 0.5) - 0.95) < 1e-9)
        #expect(abs(WindDownStage.transitionSeconds(for: 1) - 1.55) < 1e-9)
        var last = 0.0
        for p in stride(from: 0.0, through: 1.0, by: 0.1) {
            let seconds = WindDownStage.transitionSeconds(for: p)
            #expect(seconds > last)
            last = seconds
        }
    }

    @Test func starsGoFromTwelveToTwentyFour() {
        #expect(WindDownVisuals.starCount(0) == 12)
        #expect(WindDownVisuals.starCount(0.5) == 18)
        #expect(WindDownVisuals.starCount(1) == 24)
        #expect(WindDownVisuals.starCount(2) == 24 && WindDownVisuals.starCount(-1) == 12)
        var last = 0
        for p in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(WindDownVisuals.starCount(p) >= last, "stars never go back")
            last = WindDownVisuals.starCount(p)
        }
    }

    @Test func theHillsSinkTwentyFourPoints() {
        #expect(WindDownVisuals.hillSink(0) == 0 && WindDownVisuals.hillSink(1) == 24 && WindDownVisuals.hillSink(0.5) == 12)
        #expect(WindDownVisuals.hillSink(3) == 24)
    }

    @Test func theMoonTravelsAGentleArc() {
        let start = WindDownVisuals.moon(0), middle = WindDownVisuals.moon(0.5), end = WindDownVisuals.moon(1)
        #expect(start.x == 0.16 && abs(end.x - 0.84) < 1e-9)
        #expect(middle.y < start.y && middle.y < end.y, "it tops the arc in the middle")
        #expect(abs(start.y - end.y) < 1e-9, "and settles as low as it began")
        var lastX = 0.0
        for p in stride(from: 0.0, through: 1.0, by: 0.05) {
            let point = WindDownVisuals.moon(p)
            #expect(point.x >= lastX && point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1)
            lastX = point.x
        }
    }

    @Test func theBackgroundMovesFromNightToDeep() {
        #expect(WindDownVisuals.background(0) == 0 && WindDownVisuals.background(1) == 1 && WindDownVisuals.background(0.4) == 0.4)
    }

    @Test func reduceMotionHasFiveCheckpoints() {
        #expect(WindDownVisuals.checkpoint(0) == 0)
        #expect(WindDownVisuals.checkpoint(0.24) == 0)
        #expect(WindDownVisuals.checkpoint(0.25) == 0.25)
        #expect(WindDownVisuals.checkpoint(0.49) == 0.25)
        #expect(WindDownVisuals.checkpoint(0.5) == 0.5)
        #expect(WindDownVisuals.checkpoint(0.74) == 0.5)
        #expect(WindDownVisuals.checkpoint(0.75) == 0.75)
        #expect(WindDownVisuals.checkpoint(0.999) == 0.75)
        #expect(WindDownVisuals.checkpoint(1) == 1)
        let seen = Set(stride(from: 0.0, through: 1.0, by: 0.01).map { WindDownVisuals.checkpoint($0) })
        #expect(seen == [0, 0.25, 0.5, 0.75, 1])
    }
}

nonisolated struct WindDownCountdownTests {
    @Test func minutesUntilTheLastMinuteThenSeconds() {
        #expect(WindDownCountdown.metric(remaining: 1200).plain == "20min")
        #expect(WindDownCountdown.metric(remaining: 1200).spoken == "20 minutes")
        #expect(WindDownCountdown.metric(remaining: 1141).plain == "20min")
        #expect(WindDownCountdown.metric(remaining: 1140).plain == "19min")
        #expect(WindDownCountdown.metric(remaining: 61).plain == "2min")
        #expect(WindDownCountdown.metric(remaining: 60.5).plain == "2min")
        #expect(WindDownCountdown.metric(remaining: 60).plain == "60s")
        #expect(WindDownCountdown.metric(remaining: 42.3).plain == "43s")
        #expect(WindDownCountdown.metric(remaining: 42.3).spoken == "43 seconds")
        #expect(WindDownCountdown.metric(remaining: 1).spoken == "1 second")
        #expect(WindDownCountdown.metric(remaining: 0).plain == "0s")
        #expect(WindDownCountdown.metric(remaining: -5).plain == "0s")
        #expect(WindDownCountdown.metric(remaining: 120).spoken == "2 minutes")
    }
}

// MARK: - The view model

nonisolated final class FakeIdleTimer: IdleTimerControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [Bool] = []
    func setDisabled(_ disabled: Bool) { lock.withLock { calls.append(disabled) } }
    var history: [Bool] { lock.withLock { calls } }
    var isDisabled: Bool { lock.withLock { calls.last ?? false } }
}

nonisolated final class FakeSessionStore: WindDownSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var began: [(id: UUID, start: Date, minutes: Int)] = []
    private var finished: [(id: UUID, completed: Bool)] = []
    func begin(start: Date, plannedMinutes: Int) async -> UUID {
        let id = UUID()
        lock.withLock { began.append((id, start, plannedMinutes)) }
        return id
    }
    func finish(_ id: UUID, completed: Bool) async { lock.withLock { finished.append((id, completed)) } }
    var beganSessions: [(id: UUID, start: Date, minutes: Int)] { lock.withLock { began } }
    var finishedSessions: [(id: UUID, completed: Bool)] { lock.withLock { finished } }
}

@MainActor
struct WindDownViewModelTests {
    final class Haptics { var count = 0 }

    struct Bench {
        let model: WindDownViewModel
        let player: PlayerBench
        let idle: FakeIdleTimer
        let store: FakeSessionStore
        let haptics: Haptics
        let alarmBackend: MockAlarmBackend
        var time: ManualTime { player.time }
    }

    static func make(suite: String = UUID().uuidString) -> Bench {
        let player = PlayerBench.make()
        let idle = FakeIdleTimer()
        let store = FakeSessionStore()
        let haptics = Haptics()
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let backend = MockAlarmBackend(mode: .authorized)
        let alarm = AlarmService(backend: backend, store: MemoryAlarmStore(), defaultMinutes: { 7 * 60 })
        let time = player.time
        let model = WindDownViewModel(
            player: player.player, alarm: alarm, store: store, idle: idle, preferences: AppPreferences(defaults: defaults), now: { time.now },
            haptic: { haptics.count += 1 }, sleeper: { await time.sleep($0) }
        )
        return Bench(model: model, player: player, idle: idle, store: store, haptics: haptics, alarmBackend: backend)
    }

    @Test func startsIdleWithTwentyMinutesAndNoSound() {
        let bench = Self.make()
        #expect(bench.model.state == .idle && bench.model.plannedMinutes == 20 && bench.model.sound == nil)
        #expect(bench.model.progress == 0 && bench.model.remaining == 1200 && bench.model.stage == .full)
        #expect(bench.idle.history.isEmpty)
    }

    @Test func theChoicesCanOnlyBeMadeBeforeBeginning() {
        let bench = Self.make()
        bench.model.choose(minutes: 30)
        bench.model.choose(sound: .rain)
        #expect(bench.model.plannedMinutes == 30 && bench.model.sound == .rain && bench.model.remaining == 1800)
        bench.model.choose(minutes: 17)
        #expect(bench.model.plannedMinutes == 30, "17 is not an option")
        bench.model.begin()
        bench.model.choose(minutes: 10)
        bench.model.choose(sound: nil)
        #expect(bench.model.plannedMinutes == 30 && bench.model.sound == .rain)
    }

    @Test func beginningKeepsTheScreenAwakeStartsTheSoundAndRemembersTheSession() async {
        let bench = Self.make()
        bench.model.choose(minutes: 10)
        bench.model.choose(sound: .ocean)
        bench.model.begin()
        await bench.time.settle()
        #expect(bench.model.state == .running && bench.model.soundIsOn)
        #expect(bench.idle.isDisabled)
        #expect(bench.player.player.state.kind == .ocean && bench.player.player.state.phase == .playing)
        #expect(bench.haptics.count == 1)
        #expect(bench.store.beganSessions.count == 1)
        #expect(bench.store.beganSessions.first?.minutes == 10)
        #expect(bench.store.beganSessions.first?.start == bench.time.now)
    }

    @Test func beginningWithoutASoundPlaysNothing() {
        let bench = Self.make()
        bench.model.begin()
        #expect(bench.model.state == .running && !bench.model.soundIsOn)
        #expect(bench.player.player.state.phase == .stopped && bench.player.engine.calls.isEmpty)
    }

    @Test func beginningTwiceIsOneSession() async {
        let bench = Self.make()
        bench.model.begin()
        bench.model.begin()
        await bench.time.settle()
        #expect(bench.store.beganSessions.count == 1 && bench.haptics.count == 1)
    }

    @Test func autostartBeginsAtOnceAndOnlyFromIdle() async {
        let bench = Self.make()
        bench.model.prepare(autostart: false)
        #expect(bench.model.state == .idle)
        bench.model.prepare(autostart: true)
        #expect(bench.model.state == .running)
        await bench.time.advance(100)
        bench.model.prepare(autostart: true)
        #expect(bench.model.state == .running && bench.model.progress > 0, "a session under way is left alone")
        #expect(bench.store.beganSessions.count == 1)
    }

    @Test func progressComesFromTheClockOnceASecond() async {
        let bench = Self.make()
        bench.model.begin()
        await bench.time.advance(120)
        #expect(bench.model.progress == 0.1 && bench.model.remaining == 1080)
        #expect(bench.model.stage == .full)
        await bench.time.advance(240)
        #expect(bench.model.progress == 0.3 && bench.model.stage == .reduced)
        await bench.time.advance(360)
        #expect(bench.model.progress == 0.6 && bench.model.stage == .minimal)
    }

    @Test func pausingStopsTheClockAndResumingContinuesIt() async {
        let bench = Self.make()
        bench.model.begin()
        await bench.time.advance(120)
        bench.model.pause()
        #expect(bench.model.state == .paused && bench.model.progress == 0.1)
        await bench.time.advance(600)
        #expect(bench.model.progress == 0.1 && bench.model.state == .paused)
        #expect(bench.time.pending == 0, "nothing ticks while paused")
        bench.model.resume()
        #expect(bench.model.state == .running)
        await bench.time.advance(120)
        #expect(bench.model.progress == 0.2)
    }

    @Test func comingBackAfterBeingAwayCatchesUpAtOnce() {
        let bench = Self.make()
        bench.model.begin()
        // The phone was locked for 14 minutes; the sound played on and nothing ticked the screen.
        bench.time.shift(by: 840)
        bench.model.sceneBecameActive()
        #expect(abs(bench.model.progress - 0.7) < 1e-9 && bench.model.state == .running && bench.model.stage == .minimal)
    }

    @Test func comingBackAfterItWouldHaveEndedEndsIt() async {
        let bench = Self.make()
        bench.model.choose(sound: .rain)
        bench.model.begin()
        bench.time.shift(by: 5000)
        bench.model.sceneBecameActive()
        #expect(bench.model.state == .ending && !bench.model.endedEarly && bench.model.progress == 1)
        await bench.time.advance(3)
        #expect(bench.model.state == .finished)
    }

    @Test func runningItsWholeTimeEndsWithAHapticAFadedSoundAndASessionMarkedCompleted() async {
        let bench = Self.make()
        bench.model.choose(minutes: 10)
        bench.model.choose(sound: .rain)
        bench.model.begin()
        await bench.time.advance(599)
        #expect(bench.model.state == .running)
        await bench.time.advance(2)
        #expect(bench.model.state == .ending && !bench.model.endedEarly && bench.model.progress == 1)
        #expect(bench.haptics.count == 2, "begin and the end")
        #expect(bench.idle.isDisabled == false, "the screen may sleep again")
        // The sound fades over four seconds, then stops cleanly.
        let fade = bench.player.engine.commands.last
        #expect(fade?.fader == 0 && fade?.faderSeconds == 4)
        await bench.time.advance(3)
        #expect(bench.model.state == .finished)
        await bench.time.advance(2)
        #expect(bench.player.player.state.phase == .stopped && !bench.player.session.active)
        #expect(bench.store.finishedSessions.map(\.completed) == [true])
        #expect(bench.store.finishedSessions.first?.id == bench.store.beganSessions.first?.id)
        #expect(bench.time.pending == 0)
        #expect(bench.idle.history == [true, false])
    }

    @Test func endingEarlyFadesTheSoundAndMarksTheSessionNotCompleted() async {
        let bench = Self.make()
        bench.model.choose(sound: .wind)
        bench.model.begin()
        await bench.time.advance(300)
        bench.model.end()
        #expect(bench.model.state == .ending && bench.model.endedEarly)
        #expect(bench.model.progress == 0.25, "where it was, not forced to the end")
        #expect(bench.haptics.count == 2 && !bench.idle.isDisabled && !bench.model.soundIsOn)
        #expect(bench.player.engine.commands.last?.fader == 0)
        await bench.time.advance(3)
        #expect(bench.model.state == .finished)
        await bench.time.advance(2)
        #expect(bench.store.finishedSessions.map(\.completed) == [false])
        #expect(bench.player.player.state.phase == .stopped)
    }

    @Test func endingWithoutASoundJustEnds() async {
        let bench = Self.make()
        bench.model.begin()
        bench.model.end()
        await bench.time.advance(3)
        #expect(bench.model.state == .finished && bench.player.engine.calls.isEmpty)
    }

    @Test func endingWhilePausedAlsoEnds() async {
        let bench = Self.make()
        bench.model.begin()
        await bench.time.advance(60)
        bench.model.pause()
        bench.model.end()
        #expect(bench.model.state == .ending && bench.model.endedEarly)
        await bench.time.advance(3)
        #expect(bench.model.state == .finished)
    }

    @Test func theSoundCanBeSwitchedOffAndOnDuringTheSession() async {
        let bench = Self.make()
        bench.model.choose(sound: .rain)
        bench.model.begin()
        #expect(bench.model.soundIsOn)
        bench.model.toggleSound()
        #expect(!bench.model.soundIsOn)
        await bench.time.advance(1.5)
        #expect(bench.player.player.state.phase == .stopped)
        bench.model.toggleSound()
        #expect(bench.model.soundIsOn && bench.player.player.state.kind == .rain && bench.player.player.state.phase == .playing)
    }

    @Test func theFinishCardKnowsTheAlarm() async {
        let bench = Self.make()
        bench.model.begin()
        bench.model.end()
        await bench.time.advance(3)
        #expect(bench.model.alarm?.state == .off)
        #expect(WindDownFinishContent.make(alarm: bench.model.alarm, clock: { _ in "7:00 AM" }) == WindDownFinishContent(alarmLine: nil, showsSetAlarm: true))
        let armed = AlarmStatus(settings: AlarmSettings(minutesSinceMidnight: 420, lastState: .armed), state: .armed, authorization: .authorized)
        let on = WindDownFinishContent.make(alarm: armed, clock: { _ in "7:00 AM" })
        #expect(on.alarmLine == "Alarm set for 7:00 AM" && !on.showsSetAlarm)
        let unavailable = AlarmStatus(settings: AlarmSettings(minutesSinceMidnight: 420), state: .unavailable, authorization: .unavailable)
        #expect(!WindDownFinishContent.make(alarm: unavailable, clock: { _ in "7:00 AM" }).showsSetAlarm)
    }

    @Test func doneReturnsToTheStartAndASecondSessionIsFresh() async {
        let bench = Self.make()
        bench.model.begin()
        bench.model.end()
        await bench.time.advance(3)
        bench.model.done()
        #expect(bench.model.state == .idle && bench.model.progress == 0 && !bench.model.endedEarly)
        bench.model.begin()
        await bench.time.settle()
        #expect(bench.model.state == .running && bench.store.beganSessions.count == 2)
    }

    @Test func theLastChoicesAreRemembered() {
        let suite = "winddown-prefs-test"
        let first = Self.make(suite: suite)
        first.model.choose(minutes: 30)
        first.model.choose(sound: .fireplace)
        first.model.begin()
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        #expect(defaults.integer(forKey: WindDownViewModel.minutesKey) == 30)
        #expect(defaults.string(forKey: WindDownViewModel.soundKey) == "fireplace")
        let player = PlayerBench.make()
        let again = WindDownViewModel(player: player.player, alarm: AlarmService(backend: MockAlarmBackend(), store: MemoryAlarmStore(), defaultMinutes: { 420 }), store: FakeSessionStore(), idle: FakeIdleTimer(), preferences: AppPreferences(defaults: defaults))
        #expect(again.plannedMinutes == 30 && again.sound == .fireplace)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func settingsChangesShowWhenTheScreenNextOpens() {
        let suite = "winddown-settings-test"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        let player = PlayerBench.make()
        let model = WindDownViewModel(
            player: player.player, alarm: AlarmService(backend: MockAlarmBackend(), store: MemoryAlarmStore(), defaultMinutes: { 420 }),
            store: FakeSessionStore(), idle: FakeIdleTimer(), preferences: preferences
        )
        #expect(model.plannedMinutes == 20 && model.sound == nil)
        preferences.update {
            $0.windDownMinutes = 10
            $0.windDownSound = .rain
        }
        #expect(model.plannedMinutes == 20, "nothing moves under an open screen until it is opened again")
        model.prepare(autostart: false)
        #expect(model.plannedMinutes == 10 && model.sound == .rain && model.remaining == 600)
        model.begin()
        preferences.update { $0.windDownMinutes = 30 }
        model.prepare(autostart: false)
        #expect(model.plannedMinutes == 10, "a session under way is left alone")
    }

    @Test func nothingTicksOnceItIsOver() async {
        let bench = Self.make()
        bench.model.begin()
        bench.model.end()
        await bench.time.advance(5)
        #expect(bench.time.pending == 0 && bench.model.state == .finished)
    }
}
