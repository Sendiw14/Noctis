import Foundation
import Testing

@testable import SoundKit

// MARK: - Fakes and a manual clock

/// A clock the test moves by hand, and a `sleep` that waits for it.
nonisolated final class ManualTime: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private var waiters: [(id: Int, wake: Date, continuation: CheckedContinuation<Void, Never>)] = []
    private var next = 0

    init(start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }

    var now: Date { lock.withLock { current } }

    fileprivate func advanceSilently(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
    var pending: Int { lock.withLock { waiters.count } }

    func sleep(_ seconds: TimeInterval) async {
        if seconds <= 0 { return }
        let id = lock.withLock { () -> Int in next += 1; return next }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.withLock { waiters.append((id, current.addingTimeInterval(seconds), continuation)) }
            }
        } onCancel: {
            let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                guard let index = waiters.firstIndex(where: { $0.id == id }) else { return nil }
                return waiters.remove(at: index).continuation
            }
            waiter?.resume()
        }
    }

    /// Moves the clock on and lets whatever was waiting for that moment run.
    @MainActor
    func advance(_ seconds: TimeInterval) async {
        // A task that was just started hasn't gone to sleep yet: let it, so it is waiting for this moment.
        await settle()
        let target = lock.withLock { current.addingTimeInterval(seconds) }
        // In steps, so a sleeper that wakes and sleeps again sees each moment it asked for.
        while true {
            let due = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                let soonest = waiters.map(\.wake).min()
                guard let soonest, soonest <= target else { current = target; return [] }
                current = max(current, soonest)
                let ready = waiters.filter { $0.wake <= soonest }
                waiters.removeAll { $0.wake <= soonest }
                return ready.map(\.continuation)
            }
            if due.isEmpty { break }
            for continuation in due { continuation.resume() }
            await settle()
        }
        await settle()
    }

    @MainActor
    func settle() async {
        for _ in 0..<8 { await Task.yield() }
    }
}

@MainActor
final class FakeEngine: SoundEngineDriving {
    var calls: [String] = []
    var commands: [SoundCommand] = []
    var running = false
    var startError: (any Error)?
    var meterHandler: (@Sendable (Float) -> Void)?
    var meterInstalls = 0
    var rebuilds = 0

    func start() throws {
        if let startError { throw startError }
        running = true
        calls.append("start")
    }

    func pause() { running = false; calls.append("pause") }
    func stop() { running = false; calls.append("stop") }
    func send(_ command: SoundCommand) { commands.append(command) }

    func setMeter(_ handler: (@Sendable (Float) -> Void)?) {
        if handler != nil, meterHandler == nil { meterInstalls += 1 }
        meterHandler = handler
    }

    func rebuild() { rebuilds += 1; running = false; calls.append("rebuild") }

    var meterOn: Bool { meterHandler != nil }
    var last: SoundCommand? { commands.last }
}

@MainActor
final class FakeSession: SoundSessionDriving {
    var onEvent: ((SoundSessionEvent) -> Void)?
    var active = false
    var activations = 0
    var deactivations = 0
    func activate() throws { active = true; activations += 1 }
    func deactivate() { active = false; deactivations += 1 }
}

@MainActor
final class FakeNowPlaying: SoundNowPlayingDriving {
    var onCommand: ((SoundRemoteCommand) -> Void)?
    var shown: [(title: String, playing: Bool)] = []
    var cleared = 0
    func show(title: String, isPlaying: Bool) { shown.append((title, isPlaying)) }
    func clear() { cleared += 1; shown = [] }
}

struct StartFailure: Error {}

@MainActor
struct PlayerBench {
    let player: SoundPlayer
    let engine: FakeEngine
    let session: FakeSession
    let nowPlaying: FakeNowPlaying
    let time: ManualTime
    let defaults: UserDefaults

    static func make(suite: String = UUID().uuidString) -> PlayerBench {
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let engine = FakeEngine()
        let session = FakeSession()
        let nowPlaying = FakeNowPlaying()
        let time = ManualTime()
        let player = SoundPlayer(
            engine: engine, session: session, nowPlaying: nowPlaying, defaults: defaults,
            now: { time.now }, sleeper: { seconds in await time.sleep(seconds) }
        )
        return PlayerBench(player: player, engine: engine, session: session, nowPlaying: nowPlaying, time: time, defaults: defaults)
    }
}

// MARK: - The state machine

nonisolated struct SoundPlaybackPolicyTests {
    typealias Step = (SoundPlaybackPhase, SoundPlaybackEvent, SoundPlaybackPhase, SoundPlaybackAction)

    static let table: [Step] = [
        (.stopped, .play, .playing, .start),
        (.stopped, .remotePlay, .playing, .start),
        (.playing, .play, .playing, .none),
        (.paused, .play, .playing, .resume),
        (.interrupted, .play, .playing, .resume),
        (.paused, .remotePlay, .playing, .resume),
        (.interrupted, .remotePlay, .playing, .resume),
        (.playing, .pause, .paused, .fadeAndPause),
        (.playing, .remotePause, .paused, .fadeAndPause),
        (.interrupted, .pause, .paused, .none),
        (.interrupted, .remotePause, .paused, .none),
        (.playing, .remoteToggle, .paused, .fadeAndPause),
        (.paused, .remoteToggle, .playing, .resume),
        (.interrupted, .remoteToggle, .playing, .resume),
        (.stopped, .stop, .stopped, .none),
        (.playing, .stop, .stopped, .fadeAndStop),
        (.paused, .stop, .stopped, .fadeAndStop),
        (.interrupted, .stop, .stopped, .fadeAndStop),
        (.playing, .timerFinished, .stopped, .stopNow),
        (.paused, .timerFinished, .stopped, .stopNow),
        (.interrupted, .timerFinished, .stopped, .stopNow),
        (.stopped, .timerFinished, .stopped, .none),
        (.playing, .interruptionBegan, .interrupted, .pauseNow),
        (.interrupted, .interruptionEnded(shouldResume: true), .playing, .resume),
        (.interrupted, .interruptionEnded(shouldResume: false), .interrupted, .none),
        (.playing, .routeLost, .paused, .pauseNow),
        (.playing, .mediaServicesReset, .playing, .rebuildAndResume),
        (.paused, .mediaServicesReset, .paused, .rebuild),
        (.interrupted, .mediaServicesReset, .interrupted, .rebuild),
    ]

    @Test(arguments: table.indices)
    func everyTransitionThatExists(index: Int) {
        let (from, event, to, action) = Self.table[index]
        let result = SoundPlaybackPolicy.reduce(from, event)
        #expect(result.phase == to, Comment(rawValue: "\(from) + \(event)"))
        #expect(result.action == action, Comment(rawValue: "\(from) + \(event)"))
    }

    @Test func everyOtherPairChangesNothing() {
        let phases: [SoundPlaybackPhase] = [.stopped, .playing, .paused, .interrupted]
        let events: [SoundPlaybackEvent] = [
            .play, .pause, .stop, .interruptionBegan, .interruptionEnded(shouldResume: true), .interruptionEnded(shouldResume: false),
            .routeLost, .mediaServicesReset, .timerFinished, .remotePlay, .remotePause, .remoteToggle,
        ]
        for phase in phases {
            for event in events where !Self.table.contains(where: { $0.0 == phase && $0.1 == event }) {
                let result = SoundPlaybackPolicy.reduce(phase, event)
                #expect(result.phase == phase && result.action == .none, Comment(rawValue: "\(phase) + \(event) did \(result)"))
            }
        }
    }

    @Test func aPausedSoundIsNeverResumedBySomeoneElse() {
        // Paused by the person, then a call comes and goes with shouldResume: it stays paused.
        var result = SoundPlaybackPolicy.reduce(.paused, .interruptionBegan)
        #expect(result.phase == .paused)
        result = SoundPlaybackPolicy.reduce(.paused, .interruptionEnded(shouldResume: true))
        #expect(result.phase == .paused && result.action == .none)
    }

    @Test func unpluggedHeadphonesDoNotComeBack() {
        let unplugged = SoundPlaybackPolicy.reduce(.playing, .routeLost)
        #expect(unplugged.phase == .paused)
        // A later "resume" from the system is not an event the policy has for a route.
        #expect(SoundPlaybackPolicy.reduce(unplugged.phase, .interruptionEnded(shouldResume: true)).phase == .paused)
    }
}

// MARK: - The sleep timer

struct SleepTimerPlanTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theChoicesAreFifteenToNinetyAndOff() {
        #expect(SleepTimerChoice.allCases.map(\.minutes) == [0, 15, 30, 45, 60, 90])
        #expect(SleepTimerChoice.allCases.map(\.title) == ["Off", "15 min", "30 min", "45 min", "60 min", "90 min"])
    }

    @Test func aTimerRunsThenFadesForTwentySecondsThenEnds() {
        let plan = SleepTimerPlan(start: start, choice: .minutes15)
        #expect(plan.end == start.addingTimeInterval(900))
        #expect(plan.fadeStart == start.addingTimeInterval(880))
        #expect(plan.phase(at: start) == .running)
        #expect(plan.phase(at: start.addingTimeInterval(879.9)) == .running)
        #expect(plan.phase(at: start.addingTimeInterval(880)) == .fading(remaining: 20))
        #expect(plan.phase(at: start.addingTimeInterval(890)) == .fading(remaining: 10))
        if case .fading(let left) = plan.phase(at: start.addingTimeInterval(899.9)) {
            #expect(abs(left - 0.1) < 0.001)
        } else {
            Issue.record("not fading at 899.9 s")
        }
        #expect(plan.phase(at: start.addingTimeInterval(900)) == .finished)
        #expect(plan.phase(at: start.addingTimeInterval(5000)) == .finished)
    }

    @Test func theRemainingTimeIsNeverNegative() {
        let plan = SleepTimerPlan(start: start, choice: .minutes30)
        #expect(plan.remaining(at: start) == 1800)
        #expect(plan.remaining(at: start.addingTimeInterval(1799)) == 1)
        #expect(plan.remaining(at: start.addingTimeInterval(1801)) == 0)
    }

    @Test func theNextWakeIsTheFadeThenTheEndThenNothing() {
        let plan = SleepTimerPlan(start: start, choice: .minutes45)
        #expect(plan.nextWake(after: start) == plan.fadeStart)
        #expect(plan.nextWake(after: plan.fadeStart) == plan.end)
        #expect(plan.nextWake(after: plan.end.addingTimeInterval(-1)) == plan.end)
        #expect(plan.nextWake(after: plan.end) == nil)
    }

    @Test func everyChoiceCountsFromTheClockWhateverHappenedInBetween() {
        for choice in SleepTimerChoice.allCases where choice != .off {
            let plan = SleepTimerPlan(start: start, choice: choice)
            #expect(plan.duration == Double(choice.minutes * 60))
            // Locked for the whole of it, looked at again at the end: it has ended.
            #expect(plan.phase(at: plan.end.addingTimeInterval(0.001)) == .finished)
        }
    }

    @Test func theCountdownIsReadAsAClock() {
        #expect(SleepTimerPlan.clock(1781) == "29:41")
        #expect(SleepTimerPlan.clock(1780.2) == "29:41")
        #expect(SleepTimerPlan.clock(59) == "0:59")
        #expect(SleepTimerPlan.clock(0) == "0:00")
        #expect(SleepTimerPlan.clock(-5) == "0:00")
        #expect(SleepTimerPlan.clock(5400) == "1:30:00")
        #expect(SleepTimerPlan.clock(3661) == "1:01:01")
    }
}

// MARK: - The player

@MainActor
struct SoundPlayerTests {
    @Test func startsQuietWithEachSoundAt40Percent() {
        let bench = PlayerBench.make()
        #expect(bench.player.state.phase == .stopped)
        #expect(bench.player.state.kind == nil)
        for kind in SoundKind.allCases { #expect(bench.player.state.gain(for: kind) == 0.4) }
        #expect(!bench.engine.running && !bench.session.active)
        #expect(bench.engine.calls.isEmpty && bench.engine.commands.isEmpty)
        #expect(bench.nowPlaying.shown.isEmpty)
    }

    @Test func playingStartsTheSessionAndTheEngineAndFadesIn() {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        #expect(bench.player.state.phase == .playing && bench.player.state.kind == .rain)
        #expect(bench.session.active && bench.session.activations == 1)
        #expect(bench.engine.running && bench.engine.calls == ["start"])
        #expect(bench.engine.last == SoundCommand(kind: .rain, gain: 0.4, fader: 1, faderSeconds: 0.3, crossfadeSeconds: 0))
        #expect(bench.nowPlaying.shown.last?.title == "Rain" && bench.nowPlaying.shown.last?.playing == true)
    }

    @Test func playingTheSameSoundAgainDoesNothing() {
        let bench = PlayerBench.make()
        bench.player.play(.ocean)
        let commands = bench.engine.commands.count
        bench.player.play(.ocean)
        #expect(bench.engine.commands.count == commands && bench.engine.calls == ["start"])
    }

    @Test func switchingCrossesOverOneAndAHalfSecondsWithoutRestarting() {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        bench.player.play(.wind)
        #expect(bench.player.state.kind == .wind && bench.player.state.phase == .playing)
        #expect(bench.engine.last == SoundCommand(kind: .wind, gain: 0.4, fader: 1, faderSeconds: 0, crossfadeSeconds: 1.5))
        #expect(bench.engine.calls == ["start"] && bench.session.activations == 1)
        #expect(bench.nowPlaying.shown.last?.title == "Wind")
    }

    @Test func pausingFadesThenPausesTheEngineAndKeepsTheSound() async {
        let bench = PlayerBench.make()
        bench.player.play(.brown)
        bench.player.pause()
        #expect(bench.player.state.phase == .paused && bench.player.state.kind == .brown)
        #expect(bench.engine.last == SoundCommand(kind: .brown, gain: 0.4, fader: 0, faderSeconds: 0.3, crossfadeSeconds: 0))
        #expect(bench.engine.running, "still running while it fades")
        await bench.time.advance(0.4)
        #expect(!bench.engine.running && bench.engine.calls == ["start", "pause"])
        #expect(bench.session.active, "the session is kept so that resuming is instant")
        #expect(bench.nowPlaying.shown.last?.playing == false)
        #expect(bench.time.pending == 0)
    }

    @Test func resumingStartsTheEngineAndFadesBackIn() async {
        let bench = PlayerBench.make()
        bench.player.play(.fireplace)
        bench.player.pause()
        await bench.time.advance(0.4)
        bench.player.resume()
        #expect(bench.player.state.phase == .playing)
        #expect(bench.engine.running && bench.engine.calls == ["start", "pause", "start"])
        #expect(bench.engine.last?.fader == 1 && bench.engine.last?.faderSeconds == 0.3)
    }

    @Test func playingAgainDuringAPausesFadeKeepsTheEngineRunning() async {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        bench.player.pause()
        bench.player.resume()
        await bench.time.advance(1)
        #expect(bench.engine.running)
        #expect(!bench.engine.calls.contains("pause"), "the late pause must not fire")
    }

    @Test func stoppingFadesThenStopsTheEngineAndLetsTheSessionGo() async {
        let bench = PlayerBench.make()
        bench.player.play(.ambient)
        bench.player.stop()
        #expect(bench.player.state.phase == .stopped && bench.player.state.kind == nil)
        #expect(bench.nowPlaying.cleared == 1)
        await bench.time.advance(0.4)
        #expect(bench.engine.calls == ["start", "stop"] && !bench.engine.running)
        #expect(!bench.session.active && bench.session.deactivations == 1)
        #expect(!bench.engine.meterOn)
        #expect(bench.time.pending == 0)
    }

    @Test func playingDuringAStopsFadeCancelsTheStop() async {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        bench.player.stop()
        bench.player.play(.wind)
        await bench.time.advance(1)
        #expect(bench.player.state.phase == .playing && bench.player.state.kind == .wind)
        #expect(!bench.engine.calls.contains("stop"))
        #expect(bench.session.active)
    }

    @Test func anEngineThatWillNotStartLeavesNothingPlaying() {
        let bench = PlayerBench.make()
        bench.engine.startError = StartFailure()
        bench.player.play(.rain)
        #expect(bench.player.state.phase == .stopped && bench.player.state.kind == nil)
        #expect(!bench.session.active)
        #expect(bench.nowPlaying.shown.isEmpty)
    }

    // MARK: Gains

    @Test func eachSoundRemembersItsOwnGain() {
        let bench = PlayerBench.make(suite: "sounds-gains-test")
        bench.player.setGain(0.7, for: .rain)
        bench.player.setGain(0.15, for: .wind)
        #expect(bench.player.state.gain(for: .rain) == 0.7 && bench.player.state.gain(for: .wind) == 0.15)
        #expect(bench.player.state.gain(for: .ocean) == 0.4)
        // A new player reads them back.
        let again = SoundPlayer(engine: FakeEngine(), session: FakeSession(), nowPlaying: FakeNowPlaying(), defaults: bench.defaults)
        #expect(again.state.gain(for: .rain) == 0.7 && again.state.gain(for: .wind) == 0.15 && again.state.gain(for: .brown) == 0.4)
    }

    @Test func aGainIsKeptBetweenZeroAndOne() {
        let bench = PlayerBench.make()
        bench.player.setGain(3, for: .rain)
        #expect(bench.player.state.gain(for: .rain) == 1)
        bench.player.setGain(-1, for: .rain)
        #expect(bench.player.state.gain(for: .rain) == 0)
    }

    @Test func movingTheSliderOfThePlayingSoundLeavesTheFaderAlone() {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        let commands = bench.engine.commands.count
        bench.player.setGain(0.9, for: .rain)
        #expect(bench.engine.commands.count == commands + 1)
        #expect(bench.engine.last == SoundCommand(kind: .rain, gain: 0.9, fader: nil, faderSeconds: 0, crossfadeSeconds: 0))
        // Another sound's slider says nothing to the engine.
        bench.player.setGain(0.2, for: .wind)
        #expect(bench.engine.commands.count == commands + 1)
    }

    @Test func aSoundStartsAtItsOwnRememberedGain() {
        let bench = PlayerBench.make()
        bench.player.setGain(0.65, for: .ocean)
        bench.player.play(.ocean)
        #expect(bench.engine.last?.gain == 0.65)
    }

    // MARK: The sleep timer

    @Test func theTimerFadesForTwentySecondsThenStopsCleanly() async {
        let bench = PlayerBench.make()
        var finished = 0
        bench.player.onTimerFinished = { finished += 1 }
        bench.player.play(.rain)
        bench.player.setTimer(.minutes15)
        #expect(bench.player.state.timer == SleepTimerPlan(start: bench.time.now, choice: .minutes15))
        await bench.time.advance(879)
        #expect(bench.player.state.phase == .playing && bench.engine.last?.fader == 1)
        await bench.time.advance(1.5)
        // The fade began at the 20 second mark, exactly: to silence over all of it.
        let fade = bench.engine.last
        #expect(fade?.fader == 0)
        #expect(abs((fade?.faderSeconds ?? 0) - 20) < 0.01)
        #expect(bench.player.state.phase == .playing)
        await bench.time.advance(19.6)
        #expect(bench.player.state.phase == .stopped && bench.player.state.kind == nil)
        #expect(bench.player.state.timer == nil && bench.player.state.timerFinished)
        #expect(bench.engine.calls.last == "stop" && !bench.engine.running)
        #expect(!bench.session.active && bench.session.deactivations == 1)
        #expect(bench.nowPlaying.cleared >= 1)
        #expect(finished == 1)
        #expect(bench.time.pending == 0, "nothing is left waiting once it has ended")
    }

    @Test func theTimerFadeIsTheLastTwentySecondsExactly() async {
        let bench = PlayerBench.make()
        bench.player.play(.wind)
        bench.player.setTimer(.minutes30)
        await bench.time.advance(1780.0)
        #expect(bench.engine.last?.fader == 0)
        #expect(abs((bench.engine.last?.faderSeconds ?? 0) - 20) < 0.01)
    }

    @Test func callingTheTimerOffBringsBackTheSoundIfItHadBegunToFade() async {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        bench.player.setTimer(.minutes15)
        await bench.time.advance(885)
        #expect(bench.engine.last?.fader == 0)
        bench.player.setTimer(.off)
        #expect(bench.player.state.timer == nil)
        #expect(bench.engine.last?.fader == 1 && bench.engine.last?.faderSeconds == 0.5)
        await bench.time.advance(2000)
        #expect(bench.player.state.phase == .playing, "it never ended")
        #expect(bench.time.pending == 0)
    }

    @Test func aTimerBeforeItsFadeIsCancelledWithoutTouchingTheSound() async {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        bench.player.setTimer(.minutes60)
        let commands = bench.engine.commands.count
        bench.player.setTimer(.off)
        #expect(bench.engine.commands.count == commands)
        #expect(bench.time.pending == 0)
    }

    @Test func aNewTimerReplacesTheOld() async {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        bench.player.setTimer(.minutes15)
        await bench.time.advance(300)
        bench.player.setTimer(.minutes45)
        #expect(bench.player.state.timer?.start == bench.time.now)
        await bench.time.advance(900)
        #expect(bench.player.state.phase == .playing, "the first timer is gone")
    }

    @Test func aTimerNeedsASoundToStop() {
        let bench = PlayerBench.make()
        bench.player.setTimer(.minutes30)
        #expect(bench.player.state.timer == nil)
        #expect(bench.time.pending == 0)
    }

    @Test func pausingDoesNotStopTheTimerButStoppingDoes() async {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        bench.player.setTimer(.minutes15)
        bench.player.pause()
        #expect(bench.player.state.timer != nil)
        bench.player.stop()
        #expect(bench.player.state.timer == nil)
        await bench.time.advance(2000)
        #expect(bench.time.pending == 0 && !bench.player.state.timerFinished)
    }

    @Test func aTimerThatEndedWhileTheAppWasAwayEndsWhenItReturns() {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        bench.player.setTimer(.minutes15)
        // The phone was locked and nothing woke the app; the clock is past the end.
        bench.time.shift(by: 1000)
        bench.player.reconcile()
        #expect(bench.player.state.phase == .stopped && bench.player.state.timerFinished)
        #expect(!bench.session.active)
    }

    @Test func aNewSoundClearsSleepWell() async {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        bench.player.setTimer(.minutes15)
        await bench.time.advance(901)
        #expect(bench.player.state.timerFinished)
        bench.player.play(.wind)
        #expect(!bench.player.state.timerFinished)
    }

    // MARK: The system

    @Test func aCallPausesAtOnceAndResumesOnlyWhenTheSystemSaysTo() {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        bench.session.emit(.interruptionBegan)
        #expect(bench.player.state.phase == .interrupted)
        #expect(bench.engine.last?.fader == 0 && bench.engine.last?.faderSeconds == 0)
        #expect(bench.engine.calls.last == "pause" && !bench.engine.running)
        bench.session.emit(.interruptionEnded(shouldResume: false))
        #expect(bench.player.state.phase == .interrupted && !bench.engine.running)
        bench.session.emit(.interruptionEnded(shouldResume: true))
        // Only from the call the system had just ended: the player was interrupted again first.
        #expect(bench.player.state.phase == .playing && bench.engine.running)
    }

    @Test func anInterruptionThatShouldResumeResumes() {
        let bench = PlayerBench.make()
        bench.player.play(.ocean)
        bench.session.emit(.interruptionBegan)
        bench.session.emit(.interruptionEnded(shouldResume: true))
        #expect(bench.player.state.phase == .playing && bench.engine.running)
        #expect(bench.engine.last?.fader == 1)
        #expect(bench.nowPlaying.shown.last?.playing == true)
    }

    @Test func aSoundThePersonPausedStaysPausedThroughACall() async {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        bench.player.pause()
        await bench.time.advance(0.4)
        bench.session.emit(.interruptionBegan)
        bench.session.emit(.interruptionEnded(shouldResume: true))
        #expect(bench.player.state.phase == .paused && !bench.engine.running)
    }

    @Test func unpluggedHeadphonesPauseAndStayPaused() {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        bench.session.emit(.routeLost)
        #expect(bench.player.state.phase == .paused && !bench.engine.running)
        bench.session.emit(.interruptionEnded(shouldResume: true))
        #expect(bench.player.state.phase == .paused)
    }

    @Test func aMediaServicesResetRebuildsTheEngineAndKeepsPlaying() {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        bench.session.emit(.mediaServicesReset)
        #expect(bench.engine.rebuilds == 1)
        #expect(bench.player.state.phase == .playing && bench.engine.running)
        #expect(bench.engine.calls == ["start", "rebuild", "start"])
        #expect(bench.engine.last?.kind == .rain)
    }

    @Test func aResetWhilePausedOnlyRebuilds() async {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        bench.player.pause()
        await bench.time.advance(0.4)
        bench.session.emit(.mediaServicesReset)
        #expect(bench.engine.rebuilds == 1 && !bench.engine.running && bench.player.state.phase == .paused)
    }

    @Test func theLockScreenAndHeadphonesControlIt() async {
        let bench = PlayerBench.make()
        bench.player.play(.rain)
        bench.nowPlaying.onCommand?(.pause)
        #expect(bench.player.state.phase == .paused)
        await bench.time.advance(0.4)
        bench.nowPlaying.onCommand?(.play)
        #expect(bench.player.state.phase == .playing && bench.engine.running)
        bench.nowPlaying.onCommand?(.toggle)
        #expect(bench.player.state.phase == .paused)
        await bench.time.advance(0.4)
        bench.nowPlaying.onCommand?(.toggle)
        #expect(bench.player.state.phase == .playing)
    }

    @Test func aRemoteTogglePlaysNothingWhenNothingIsLoaded() {
        let bench = PlayerBench.make()
        bench.nowPlaying.onCommand?(.toggle)
        bench.nowPlaying.onCommand?(.play)
        #expect(bench.player.state.phase == .stopped)
        #expect(bench.engine.calls.isEmpty)
    }

    // MARK: The meter and the battery

    @Test func theMeterRunsOnlyWhileAskedAndPlaying() async {
        let bench = PlayerBench.make()
        bench.player.setMeterEnabled(true)
        #expect(!bench.engine.meterOn, "nothing is playing")
        bench.player.play(.rain)
        #expect(bench.engine.meterOn && bench.engine.meterInstalls == 1)
        bench.player.pause()
        #expect(!bench.engine.meterOn)
        await bench.time.advance(0.4)
        bench.player.resume()
        #expect(bench.engine.meterOn)
        bench.player.setMeterEnabled(false)
        #expect(!bench.engine.meterOn)
        bench.player.setMeterEnabled(true)
        bench.player.stop()
        #expect(!bench.engine.meterOn)
    }

    @Test func theMeterIsOffWhenTheSystemInterrupts() {
        let bench = PlayerBench.make()
        bench.player.setMeterEnabled(true)
        bench.player.play(.rain)
        bench.session.emit(.interruptionBegan)
        #expect(!bench.engine.meterOn)
        bench.session.emit(.interruptionEnded(shouldResume: true))
        #expect(bench.engine.meterOn)
    }

    @Test func aLevelFromTheMeterReachesTheScreen() async {
        let bench = PlayerBench.make()
        var levels: [Float] = []
        bench.player.onLevel = { levels.append($0) }
        bench.player.setMeterEnabled(true)
        bench.player.play(.rain)
        bench.engine.meterHandler?(0.25)
        await bench.time.settle()
        #expect(levels == [0.25])
    }

    @Test func nothingIsLeftRunningOnceItIsAllOver() async {
        let bench = PlayerBench.make()
        bench.player.setMeterEnabled(true)
        bench.player.play(.rain)
        bench.player.setTimer(.minutes15)
        bench.player.stop()
        await bench.time.advance(1)
        #expect(!bench.engine.running && !bench.engine.meterOn && !bench.session.active)
        #expect(bench.time.pending == 0 && bench.player.state.timer == nil)
        #expect(bench.nowPlaying.shown.isEmpty)
    }
}

extension FakeSession {
    func emit(_ event: SoundSessionEvent) { onEvent?(event) }
}

extension ManualTime {
    /// Moves the clock without waking anything: the phone slept.
    func shift(by seconds: TimeInterval) {
        advanceSilently(seconds)
    }
}
