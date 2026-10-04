import DesignSystem
import Foundation
import NightKit
import Observation
import SoundKit
import UIKit

/// Runs a wind-down session (APP_RULES.md R32): the state machine and the clock, the sound, the
/// screen staying awake, and what is remembered. Progress is read from the clock once a second,
/// never counted, so locking the phone loses nothing and coming back catches up at once.
@MainActor
@Observable
public final class WindDownViewModel {
    public private(set) var state: WindDownState = .idle
    /// 0...1, from the clock.
    public private(set) var progress: Double = 0
    public private(set) var remaining: TimeInterval
    public var plannedMinutes: Int
    /// The sound chosen before beginning; nil for none.
    public var sound: SoundKind?
    /// The sound is on (playing) during the session.
    public private(set) var soundIsOn = false
    /// The person ended it before its time.
    public private(set) var endedEarly = false
    /// For the finish card.
    public private(set) var alarm: AlarmStatus?

    public static let soundFadeSeconds = 4.0
    public static let endingSeconds = 2.5
    static let minutesKey = "noctis.winddown.minutes"
    static let soundKey = "noctis.winddown.sound"

    @ObservationIgnored private var clock: WindDownClock
    @ObservationIgnored private let player: SoundPlayer
    @ObservationIgnored private let alarmService: AlarmService
    @ObservationIgnored private let store: any WindDownSessionStoring
    @ObservationIgnored private let idle: any IdleTimerControlling
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleeper: @Sendable (TimeInterval) async -> Void
    @ObservationIgnored private let haptic: () -> Void
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var ending: Task<Void, Never>?
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var storeTask: Task<Void, Never>?
    @ObservationIgnored var reducedMotionOverride: Bool?

    public init(
        player: SoundPlayer, alarm: AlarmService, store: any WindDownSessionStoring, idle: any IdleTimerControlling,
        defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }, haptic: @escaping () -> Void = { NoctisHaptics.soft() },
        sleeper: @escaping @Sendable (TimeInterval) async -> Void = { seconds in try? await Task.sleep(for: .seconds(seconds)) }
    ) {
        self.player = player
        self.alarmService = alarm
        self.store = store
        self.idle = idle
        self.defaults = defaults
        self.now = now
        self.haptic = haptic
        self.sleeper = sleeper
        let saved = defaults.integer(forKey: Self.minutesKey)
        let minutes = WindDownClock.options.contains(saved) ? saved : WindDownClock.defaultMinutes
        plannedMinutes = minutes
        sound = defaults.string(forKey: Self.soundKey).flatMap(SoundKind.init(rawValue:))
        clock = WindDownClock(minutes: minutes)
        remaining = clock.plannedSeconds
    }

    // MARK: Derived

    public var stage: WindDownStage { WindDownStage.stage(for: progress) }
    public var countdown: NoctisMetricValue { WindDownCountdown.metric(remaining: remaining) }
    public var isActive: Bool { state == .running || state == .paused }

    // MARK: Before beginning

    /// The screen opened. `autostart` (a Siri-ready route) begins at once; a session already
    /// under way is left as it is, and a finished one starts over.
    public func prepare(autostart: Bool) {
        if state == .finished { reset() }
        if autostart, state == .idle { begin() }
    }

    public func choose(minutes: Int) {
        guard state == .idle, WindDownClock.options.contains(minutes) else { return }
        plannedMinutes = minutes
        clock = WindDownClock(minutes: minutes)
        remaining = clock.plannedSeconds
    }

    public func choose(sound: SoundKind?) {
        guard state == .idle else { return }
        self.sound = sound
    }

    // MARK: The session

    public func begin() {
        guard state == .idle else { return }
        state = WindDownMachine.reduce(state, .begin)
        clock = WindDownClock(minutes: plannedMinutes)
        clock.start(at: now())
        progress = 0
        remaining = clock.plannedSeconds
        endedEarly = false
        idle.setDisabled(true)
        defaults.set(plannedMinutes, forKey: Self.minutesKey)
        defaults.set(sound?.rawValue ?? "none", forKey: Self.soundKey)
        haptic()
        if let sound {
            player.play(sound)
            soundIsOn = true
        } else {
            soundIsOn = false
        }
        let start = now()
        let minutes = plannedMinutes
        storeTask = Task { [store] in
            let id = await store.begin(start: start, plannedMinutes: minutes)
            self.sessionID = id
        }
        runTicker()
    }

    public func pause() {
        guard state == .running else { return }
        state = WindDownMachine.reduce(state, .pause)
        clock.pause(at: now())
        ticker?.cancel()
        ticker = nil
        refresh()
    }

    public func resume() {
        guard state == .paused else { return }
        state = WindDownMachine.reduce(state, .resume)
        clock.resume(at: now())
        refresh()
        runTicker()
    }

    public func toggleSound() {
        if soundIsOn {
            player.fadeOutAndStop(over: 1)
            soundIsOn = false
        } else {
            let kind = sound ?? .brown
            sound = kind
            player.play(kind)
            soundIsOn = true
        }
        NoctisHaptics.selection()
    }

    /// The person ends it early.
    public func end() {
        guard isActive else { return }
        finish(completed: false)
    }

    /// The app came back to the front: the clock is read at once, whatever happened meanwhile.
    public func sceneBecameActive() {
        refresh()
    }

    /// After the finish card.
    public func done() {
        reset()
    }

    func reset() {
        ticker?.cancel()
        ticker = nil
        ending?.cancel()
        ending = nil
        state = WindDownMachine.reduce(state, .reset)
        progress = 0
        endedEarly = false
        clock = WindDownClock(minutes: plannedMinutes)
        remaining = clock.plannedSeconds
        sessionID = nil
    }

    // MARK: Clock

    /// Reads the clock: progress and time left, and the end if its time has come.
    func refresh() {
        guard isActive else { return }
        let moment = now()
        progress = clock.progress(at: moment)
        remaining = clock.remaining(at: moment)
        if clock.isComplete(at: moment) { finish(completed: true) }
    }

    private func runTicker() {
        ticker?.cancel()
        ticker = Task { [weak self, sleeper] in
            while !Task.isCancelled {
                await sleeper(1)
                if Task.isCancelled { return }
                guard let self, state == .running else { return }
                refresh()
            }
        }
    }

    private func finish(completed: Bool) {
        guard isActive else { return }
        ticker?.cancel()
        ticker = nil
        state = WindDownMachine.reduce(state, completed ? .reachedEnd : .endEarly)
        endedEarly = !completed
        if completed {
            progress = 1
            remaining = 0
        }
        // A soft haptic, the sound fading, the screen free to sleep again.
        haptic()
        if soundIsOn { player.fadeOutAndStop(over: Self.soundFadeSeconds) }
        soundIsOn = false
        idle.setDisabled(false)
        ending = Task { [weak self, sleeper] in
            await sleeper(Self.endingSeconds)
            if Task.isCancelled { return }
            await self?.settle(completed: completed)
        }
    }

    private func settle(completed: Bool) async {
        state = WindDownMachine.reduce(state, .endingDone)
        ending = nil
        await storeTask?.value
        if let sessionID { await store.finish(sessionID, completed: completed) }
        alarm = await alarmService.status()
    }
}

/// The real idle timer.
public struct ApplicationIdleTimer: IdleTimerControlling {
    public init() {}

    public func setDisabled(_ disabled: Bool) {
        Task { @MainActor in UIApplication.shared.isIdleTimerDisabled = disabled }
    }
}
